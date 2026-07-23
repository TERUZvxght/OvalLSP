class PostsController < ApplicationController
  def index
    @posts = Post.all
  end

  def show
    @post = Post.find(params[:id])
  end

  def create
    @post = Post.create(post_params)
  end

  def update
    @post = Post.find(params[:id])
    @post.update(post_params)
  end

  def destroy
    Post.find(params[:id]).destroy
  end

  private

  def post_params
    params.require(:post).permit(:title, :body)
  end
end
