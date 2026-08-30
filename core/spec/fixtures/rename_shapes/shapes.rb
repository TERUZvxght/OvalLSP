def compound
  n = 1
  n += 2
  n ||= 3
  n
end

def block_closure
  w = 1
  [1, 2].each { w = w + 1 }
  w
end

def shorthand(label:)
  label
end

def uses_shorthand
  name = "n"
  [{ name: }, shorthand(label: name)]
end

def singleton_receiver
  ty = Object.new
  def ty.outer
    :x
  end
  ty
end
