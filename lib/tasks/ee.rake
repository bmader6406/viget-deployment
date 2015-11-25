require 'yaml'
require 'erb'

require Pathname.new(File.dirname(__FILE__)).join('..', 'database')

namespace :ee do
  def system_dir
    paths = Dir.glob("#{Dir.pwd}/**/expressionengine")
    raise "Could not locate EE system path" unless paths.length == 1

    Pathname.new(paths.first).join('..').basename
  end

  def database_config
    YAML.load_file('config/config.yml')['database']
  end

  def root_path
    Pathname.new(File.expand_path(File.dirname(__FILE__))).join('..', '..')
  end

  def asset_path
    root_path.join('lib', 'viget', 'deployment', 'assets')
  end

  def ask(prompt, default = nil)
    @saved_responses ||= {}

    key = prompt.strip

    return @saved_responses[key] if @saved_responses[key]

    question = prompt
    question << "|#{default}| " if default

    print question
    response = STDIN.gets.chomp

    response = default if default && response == ''
    @saved_responses[key] = response
  end

  task :create_directories do
    directories =
      [
        "images/uploads",
        "images/captchas",
        "images/member_photos",
        "images/pm_attachments",
        "images/signature_attachments",
        "images/avatars/uploads",
        "#{system_dir}/expressionengine/cache"
      ]

    directories.each do |directory|
      FileUtils.mkdir_p(directory)
      FileUtils.cp(asset_path.join('protected.html'), "#{directory}/index.html")
      FileUtils.chmod_R(0777, directory)
    end

    puts "Created untracked folders"
  end

  task :setup => ['config:reset', 'db:initial_import', 'create_directories']

  namespace :db do
    desc "Create the database specified in the configuration file"
    task :create do |t, args|
      db = Database.new(database_config)
      db.create
    end

    desc "Drop the database specified in the configuration file"
    task :drop do |t, args|
      db = Database.new(database_config)
      db.drop
    end

    desc "Import the database from the specified dumpfile (or default)"
    task :import_from_file, [:file] do |t, args|
      args.with_defaults(:file => 'data/db_dump.sql')

      db = Database.new(database_config)
      db.import_from(args[:file])
    end

    desc "Export the database to the specified dumpfile (or default)"
    task :export_to_file, [:file] do |t, args|
      args.with_defaults(:file => 'data/db_dump.sql')

      db = Database.new(database_config)
      db.export_to(args[:file])
    end

    desc "Backup the database to a timestamped SQL file"
    task :backup, [:file] do |t, args|
      args.with_defaults(:file => Time.now.strftime('data/db_backup_%Y%m%d%H%M.sql'))

      db = Database.new(database_config)
      db.export_to(args[:file])
    end

    task :initial_import => [:create, :import_from_file]
    task :import         => [:backup, :drop, :create, :import_from_file]
    task :export         => [:export_to_file]
  end

  namespace :cache do
    namespace :stash do
      desc "Clear the Stash add-on caches"
      task :clear do
        db = Database.new(database_config)
        db.db_execute('TRUNCATE TABLE `exp_stash`')
        puts "Cleared stash cache"
      end
    end

    namespace :file do
      desc "Clear the EE filesystem caches"
      task :clear do
        file_caches = [
          "#{system_dir}/expressionengine/cache/#{db_cache}",
          "#{system_dir}/expressionengine/cache/#{db_cache}",
          "static"
        ]

        file_caches.each do |cache_path|
          puts " * Wiping cache directory: #{cache_path}"
          FileUtils.rm_rf("#{cache_path}/*")
        end
        puts "Cleared file cache"
      end
    end

    desc "Clear all available caches"
    task :clear => ['stash:clear', 'file:clear']
  end

  task :config => ['config:create']

  namespace :config do
    desc "Re-create configuration files from scratch"
    task :reset => [:remove, :create]

    desc "Generate necessary EE configuration files"
    task :create do
      ee_system = system_dir

      config_files = {
        'config.yml.erb'   => 'config/config.yml',
        'database.php.erb' => "#{system_dir}/expressionengine/config/database.php"
      }

      missing_files = config_files.values.reject {|f| File.exist?(f) }

      if missing_files.empty?
        puts "It seems as if setup has already been run. Exiting."
        exit 1
      end

      puts
      puts "This process will walk through setting up a local install of this ExpressionEngine project."
      puts "Please answer a few questions about you local mysql installation to get started"
      puts

      config_files.each do |template, destination|
        File.open(destination, 'w') do |file|
          file << ERB.new(File.read(root_path.join('templates', 'ee', template)), nil, '-').result(binding)
        end

        FileUtils.chmod(0666, destination)
      end

      puts
    end

    desc "Remove all generated EE configuration files"
    task :remove do
      files = [
        "#{system_dir}/expressionengine/config/database.php",
        "config/config.yml"
      ]

      files.each {|f| FileUtils.rm_rf(f) }
    end
  end
end