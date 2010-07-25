require 'fileutils'
require 'tmpdir'
class FckeditorController < ActionController::Base
  UPLOADED = "/user_files"
  UPLOADED_ROOT = RAILS_ROOT + "/public" + UPLOADED
  MIME_TYPES = [
   # "image/jpg",
    #"image/jpeg",
    #"image/pjpeg",
    #"image/gif",
    #"image/png",
    #"application/x-shockwave-flash",
    #"application/x-bzip",
    #"application/x-gz",
    #"application/x-tar",
    #"application/x-bzip",
    #"application/x-zip",
    #"application/x-rar"
  ]
  
  RXML = <<-EOL
  xml.instruct!
    #=> <?xml version="1.0" encoding="utf-8" ?>
  xml.Connector("command" => params[:Command], "resourceType" => 'File') do
    xml.CurrentFolder("url" => @fck_url, "path" => params[:CurrentFolder])
    xml.Folders do
      @folders.each do |folder|
        xml.Folder("name" => folder)
      end
    end if !@folders.nil?
    xml.Files do
      @files.keys.sort.each do |f|
        xml.File("name" => f, "size" => @files[f])
      end
    end if !@files.nil?
    xml.Error("number" => @errorNumber) if !@errorNumber.nil?
  end
  EOL
  
  # figure out who needs to handle this request
  def command   
    if params[:Command] == 'GetFoldersAndFiles' || params[:Command] == 'GetFolders'
      get_folders_and_files
    elsif params[:Command] == 'CreateFolder'
      create_folder
	  elsif params[:Command] == 'FileUpload'
 	    upload_file
 	  end
 	  
 	  render :inline => RXML, :type => :rxml unless params[:Command] == 'FileUpload'
 	end 
 	
  def get_folders_and_files(include_files = true)
    @folders = Array.new
    @files = {}
    begin
      @fck_url = upload_directory_path
      @current_folder = current_directory_path
      Dir.entries(@current_folder).each do |entry|
        next if entry =~ /^\./
        path = @current_folder + entry
        @folders.push entry if FileTest.directory?(path)
        @files[entry] = (File.size(path) / 1024) if (include_files and FileTest.file?(path))
      end
    rescue => e
      @errorNumber = 110 if @errorNumber.nil?
    end
  end

  def create_folder
    begin 
      @fck_url = current_directory_path
      path = @fck_url + params[:NewFolderName]
      if !session[:user_name]
	@errorNumber = 111
      elsif !(File.stat(@fck_url).writable?)
        @errorNumber = 103
      elsif params[:NewFolderName] !~ /[\w\d\s]+/
        @errorNumber = 102
      elsif params[:NewFolderName] =~ /[\.\%]+/
        @errorNumber = 102
      elsif FileTest.exists?(path)
        @errorNumber = 101
      else
        Dir.mkdir(path,0775)
        @errorNumber = 0
      end
    rescue => e
      @errorNumber = 110 if @errorNumber.nil?
    end
  end
  
  def upload_file
    @user = User.find_by_name(session[:user_name])
    I18n.locale = @user.language || "en-US"
    @limit_size = @user.get_group.file_size_limit
    begin
      @new_file = check_file(params[:NewFile])
      @fck_url = upload_directory_path
      ftype = @new_file.content_type.strip
      if !session[:user_name]
	@errorNumber = 1
	render :text => %Q'<script>window.parent.OnUploadCompleted(#{@errorNumber},null,null,\"#{t("plugins.fck.please_login")}\");</script>'
	return
      elsif @new_file.length > @limit_size.megabytes
	@errorNumber = 1
	render :text => %Q'<script>window.parent.OnUploadCompleted(#{@errorNumber},\"\",\"\",\"#{t("plugins.fck.file_size_invalid", :size => @limit_size)}\");</script>'
	return
     elsif (@user.used_space.kilobytes + @new_file.length) > (@user.get_group.space.megabytes)	
	@errorNumber = 1
	render :text => %Q'<script>window.parent.OnUploadCompleted(#{@errorNumber},null,null,\"#{t("plugins.fck.space_full")}\");</script>'
	return
      #elsif  MIME_TYPES.include?(ftype)
       # @errorNumber = 202
        #puts "#{ftype} is invalid MIME type"
        #raise "#{ftype} is invalid MIME type"
      else
        path = current_directory_path + "/" + @new_file.original_filename
        file_name = @new_file.original_filename
        if File.exist?(path)
            file_name = File.basename(file_name, ".*") + "_" + Time.now.strftime("%Y%m%d%H%M%S") + File.extname(file_name)
            path = current_directory_path + "/" + file_name 
        end
        File.open(path,"wb",0664) do |fp|
          FileUtils.copy_stream(@new_file, fp)
        end
	@user.dirty_space
        @errorNumber = 0
	render :text => %Q'<script>window.parent.OnUploadCompleted(#{@errorNumber},\"#{UPLOADED}/#{session[:user_name]}/#{params[:Type]}/#{file_name}\",\"\");</script>'
      end
    rescue => e
      @errorNumber = 110 if @errorNumber.nil?
    end
    #render :text => %Q'<script>alert("#{@errorNumber}");</script>', :layout => nil
   
  end

  def upload
    self.upload_file
  end
  
  include ActionView::Helpers::TextHelper
  def check_spelling
    require 'cgi'
    require 'fckeditor_spell_check'

    @original_text = params[:textinputs] ? params[:textinputs].first : ''
    plain_text = strip_tags(CGI.unescape(@original_text))
    @words = FckeditorSpellCheck.check_spelling(plain_text)

    render :file => "#{Fckeditor::PLUGIN_VIEWS_PATH}/fckeditor/spell_check.rhtml"
  end
  
  private
  def current_directory_path
    base_dir = "#{UPLOADED_ROOT}/#{session[:user_name]}/#{params[:Type]}"
    Dir.mkdir(base_dir,0775) unless File.exists?(base_dir)
    check_path("#{base_dir}#{params[:CurrentFolder]}")
  end
  
  def upload_directory_path
    uploaded = ActionController::Base.relative_url_root.to_s+"#{UPLOADED}/#{session[:user_name]}/#{params[:Type]}"
    "#{uploaded}#{params[:CurrentFolder]}"
  end
  
  def check_file(file)
    unless "#{file.class}" == "Tempfile" || "StringIO"
      @errorNumber = 403
      throw Exception.new
    end
    file
  end
  
  def check_path(path)
    exp_path = File.expand_path path
    if exp_path !~ %r[^#{File.expand_path(RAILS_ROOT)}/public#{UPLOADED}]
      @errorNumber = 403
      throw Exception.new
    end
    path
  end
end
