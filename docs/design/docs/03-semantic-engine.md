# 03. Semantic Engine

## 1. 目的

Semantic Engineは、Rubyコードから「この式は何を意味するか」を問い合わせ可能な内部モデルを構築する。

Prism ASTをそのままLSP機能へ直結させない。ASTは構文上の事実であり、クラス再オープン、継承、mix-in、RBS、Rails DSL、runtime snapshotを統合するには永続的なsemantic graphが必要である。

## 2. 中核データモデル

### 2.1 SymbolId

```ruby
SymbolId = Data.define(
  :kind,        # :class, :module, :instance_method, :singleton_method, ...
  :owner,       # "::User"
  :name,        # "company"
  :discriminator
)
```

例:

```text
class:::User
instance_method:::User#company
singleton_method:::User.find
route:main_app#post_path
column:::User#email
```

SymbolIdはファイル位置ではなく意味上の同一性を表す。同じclassが複数ファイルで再オープンされても同じIDに集約する。

### 2.2 Declaration

```ruby
Declaration = Data.define(
  :symbol_id,
  :location,
  :visibility,
  :parameters,
  :documentation,
  :origin,
  :confidence,
  :generation
)
```

同一symbolに複数Declarationを許可する。

### 2.3 Evidence

```ruby
Evidence = Data.define(
  :source,      # :source, :rbs, :rbi, :runtime, :rails_dsl, :observation
  :authority,   # 0..100
  :confidence,  # 0.0..1.0
  :location,
  :generation,
  :metadata
)
```

### 2.4 Type

MVP型集合:

```text
Unknown
Untyped
Never
Nil
Boolean
Literal[value]
Nominal[name, args]
SingletonClass[name]
Union[types]
Intersection[types]
Tuple[types]
Shape[key => type]
Proc[params, return]
SelfType
ClassOf[type]
TypeParameter[name]
Protocol[required_methods]
```

`Unknown`と`Untyped`を分ける。

- Unknown: まだ情報がない。追加情報で狭められる。
- Untyped: 明示的または境界上で型検査を諦める。呼び出しを許可する。

## 3. 型情報の優先順位

単純な上書きではなく、出所を保持してmergeする。

推奨authority:

| Source | Authority |
|---|---:|
| 明示的RBS/RBI signature | 100 |
| Rubyソース内の明示的型コメント/将来構文 | 100 |
| Rails reflectionで確認された構造 | 95 |
| DB schema | 95 |
| DSL adapterの決定的生成規則 | 90 |
| 静的な式・制御フロー推論 | 85 |
| method body summary | 80 |
| 規約ヒューリスティック | 55 |
| runtime observation | 50 |
| 名前ベース推定 | 20 |

runtime observationは実際に見た型ではあるが、網羅性がないためauthorityを高くしすぎない。

## 4. インデックス作成

### 4.1 1回のAST走査で収集するもの

- class/module declarations
- method definitions
- parameters
- constant assignments
- aliases
- include/prepend/extend
- attr_reader/writer/accessor
- visibility
- local variable assignments
- instance/class variable writes
- call sites
- require/require_relative
- DSL candidate calls
- comments/docstrings

Prism Dispatcher相当のvisitorを1回だけ通し、複数listenerが同じASTを繰り返し走査しないようにする。

### 4.2 ファイルサマリー

```ruby
FileSummary = Data.define(
  :uri,
  :content_hash,
  :document_version,
  :declarations,
  :references,
  :method_bodies,
  :dependencies,
  :dsl_calls,
  :diagnostics
)
```

変更時は旧FileSummaryをindexから差し引き、新Summaryを追加する。

## 5. 型推論パイプライン

```text
parse
  -> lexical binding
  -> control-flow graph
  -> constraint generation
  -> local solve
  -> call resolution
  -> method summary lookup/generation
  -> fixed point
  -> normalization/widening
```

### 5.1 ローカル推論

```ruby
user = User.new
```

制約:

```text
type(User) = SingletonClass[User]
return(User.new) = Nominal[User]
type(user) >= Nominal[User]
```

### 5.2 分岐

```ruby
value = condition ? User.new : Company.new
```

```text
type(value) = User | Company
```

### 5.3 nil narrowing

```ruby
return unless user
user.name
```

CFG上、後続blockでは`user - Nil`とする。

対応パターン:

- `if value`
- `unless value.nil?`
- `value.is_a?(Type)`
- `case value; when Type`
- `raise unless value`
- `next unless value`
- safe navigation `&.`

### 5.4 ブロック

```ruby
names = users.map { |user| user.name }
```

RBSまたは組み込みモデルから:

```text
users: Enumerable[User]
block user: User
block return: String
map return: Array[String]
```

### 5.5 メソッドサマリー

```ruby
MethodSummary = Data.define(
  :symbol_id,
  :parameter_types,
  :return_type,
  :effects,
  :dependencies,
  :confidence,
  :generation
)
```

body解析の結果をキャッシュする。依存symbolのsummary変更時だけ再計算する。

### 5.6 fixed pointとwidening

再帰・相互再帰では最大反復数を設定する。

例:

```text
iteration_limit = 8
union_member_limit = 12
literal_limit = 16
```

超過時:

- Literal群 -> 基底Nominal
- 大きなUnion -> 共通ancestorまたはUntyped
- 再帰型 -> recursive markerを除去して上位型へwiden

## 6. メソッド解決

receiver typeごとに候補を求める。

### Nominal

1. class自身
2. prepended modules
3. included modules
4. superclass chain
5. Object/Kernel/BasicObject
6. refinements（把握可能な範囲）

### Union

各memberで解決し、候補の共通部分を優先する。member固有候補はconditionalとして表示する。

### Unknown

次の順で縮退する。

1. local assignment/history
2. method return summary
3. argument passing constraints
4. RBS/RBI
5. runtime evidence
6. lexical/owner context
7. 名前ヒューリスティック
8. workspace同名候補

最後の同名候補はcompletionの下位に置き、definitionでは候補一覧として返す。

## 7. Rails型モデル

### 7.1 Active Record class methods

組み込みgeneric rule例:

```text
Model.find(id)                  -> Model
Model.find_by(...)              -> Model | nil
Model.where(...)                -> ActiveRecord::Relation[Model]
Model.all                       -> ActiveRecord::Relation[Model]
Relation[T]#first               -> T | nil
Relation[T]#first!              -> T
Relation[T]#to_a                -> Array[T]
Relation[T]#each block param    -> T
```

### 7.2 Associations

```text
belongs_to :company   -> company: Company | nil or Company
                        company=: Company
                        build_company: Company
                        create_company: Company
has_many :orders      -> orders: CollectionProxy[Order]
has_one :profile      -> profile: Profile | nil
```

optional判定はreflectionを優先する。

### 7.3 Columns

DB型からRuby型への標準mapping:

```text
integer     -> Integer
bigint      -> Integer
float       -> Float
decimal     -> BigDecimal
boolean     -> TrueClass | FalseClass
string/text -> String
datetime    -> ActiveSupport::TimeWithZone or Time
json/jsonb  -> Hash[String, Untyped] | Array[Untyped] | scalar
uuid        -> String
```

adapter/pluginで上書き可能にする。

### 7.4 Route helpers

route templateから引数を合成する。

```text
/admin/projects/:project_id/tasks/:id(.:format)
```

```text
admin_project_task_path(project_or_id, task_or_id, format: ..., anchor: ...) -> String
```

### 7.5 Controller-view dataflow

MVPでは規約ベースに限定する。

- `UsersController#show` -> `app/views/users/show.*`
- actionで代入されたinstance variableをview scopeへ伝播
- `render :edit`、`render "users/edit"`を静的に解決
- partial localsは明示的hashのみ

不明なdynamic renderは追わない。

## 8. RBS/RBI統合

RBSは`RBS::EnvironmentLoader`と`RBS::DefinitionBuilder`を使用して内部Typeへ変換する。

RBIは次のいずれかで取り込む。

1. PrismでRuby構文としてparseし、空method body + `sig`を読む。
2. RBSのRBI prototype/import機能を利用する。

MVPはRBSを先に実装し、RBIはv0.2とする。

## 9. 診断

初期診断:

- 明確に存在しない定数
- 明確に存在しないメソッド
- 必須引数不足/過多
- nil可能性があるreceiverへの通常呼び出し
- 解決不能なroute helper
- Rails snapshotとsource DSLの明確な不整合

推定に依存する診断はwarningではなくhintとし、既定で無効にする。

## 10. Query結果

```ruby
SemanticResult = Data.define(
  :value,
  :confidence,
  :evidence,
  :is_stale,
  :generation,
  :alternatives
)
```

LSPへ返す前に、UIノイズを避けるためconfidence thresholdと候補数制限を適用する。
