class UserTheme
    PATH = File.expand_path(File.join(RAILS_ROOT, "themes", "user"))
    PUBLIC_PATH =  File.expand_path(File.join(RAILS_ROOT, "public", "themes"))
    LIST = Dir[PATH + "/*"].map{|t| File.basename(t)}.sort
    COPIED = {}

    def self.file_path(theme, file)
	File.join PATH, theme, file
    end

    def self.copy_to_public(theme)
	unless COPIED[theme]
	    dst = File.join(PUBLIC_PATH, theme)
	    src = File.join(PATH, theme)
	    FileUtils.makedirs dst
	    ['images', 'stylesheets', 'javascripts', 'screenshot.png'].each do |f|
		FileUtils.cp_r File.join(src, f), dst
	    end
	    COPIED[theme] = true
	end

	rescue nil
    end

    def self.user_themes(user)
	Dir[File.join(user.base_dir, "themes") + "/*"].map{|t| File.basename(t)}.sort
    end

end
