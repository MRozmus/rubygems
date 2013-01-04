require 'rubygems/command'
require 'rubygems/dependency_list'
require 'rubygems/uninstaller'

class Gem::Commands::CleanupCommand < Gem::Command

  def initialize
    super 'cleanup',
          'Clean up old versions of installed gems in the local repository',
          :force => false, :install_dir => Gem.dir

    add_option('-d', '--dryrun', "") do |value, options|
      options[:dryrun] = true
    end

    @candidate_gems  = nil
    @default_gems    = nil
    @full            = nil
    @gems_to_cleanup = nil
    @original_home   = nil
    @original_path   = nil
    @primary_gems    = nil
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to cleanup"
  end

  def defaults_str # :nodoc:
    "--no-dryrun"
  end

  def description # :nodoc:
    <<-EOF
The cleanup command removes old gems from GEM_HOME.  If an older version is
installed elsewhere in GEM_PATH the cleanup command won't touch it.

Older gems that are required to satisify the dependencies of gems
are not removed.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [GEMNAME ...]"
  end

  def execute
    say "Cleaning up installed gems..."

    get_primary_gems
    get_candidate_gems
    get_gems_to_cleanup

    @full = Gem::DependencyList.from_specs

    deplist = Gem::DependencyList.new
    @gems_to_cleanup.uniq.each do |spec| deplist.add spec end

    deps = deplist.strongly_connected_components.flatten.reverse

    @original_home = Gem.dir
    @original_path = Gem.path

    deps.each do |spec|
      uninstall_dep spec
    end

    say "Clean Up Complete"

    if Gem.configuration.really_verbose then
      skipped = @default_gems.map { |spec| spec.full_name }

      say "Skipped default gems: #{skipped.join ', '}"
    end
  end

  def get_candidate_gems
    @candidate_gems = unless options[:args].empty? then
                        options[:args].map do |gem_name|
                          Gem::Specification.find_all_by_name gem_name
                        end.flatten
                      else
                        Gem::Specification.to_a
                      end
  end

  def get_gems_to_cleanup
    gems_to_cleanup = @candidate_gems.select { |spec|
      @primary_gems[spec.name].version != spec.version
    }

    @default_gems, @gems_to_cleanup = gems_to_cleanup.partition { |spec|
      spec.default_gem?
    }
  end

  def get_primary_gems
    @primary_gems = {}

    Gem::Specification.each do |spec|
      if @primary_gems[spec.name].nil? or
         @primary_gems[spec.name].version < spec.version then
        @primary_gems[spec.name] = spec
      end
    end
  end

  def uninstall_dep spec
    return unless @full.ok_to_remove?(spec.full_name)

    if options[:dryrun] then
      say "Dry Run Mode: Would uninstall #{spec.full_name}"
      return
    end

    say "Attempting to uninstall #{spec.full_name}"

    options[:args] = [spec.name]

    uninstall_options = {
      :executables => false,
      :version => "= #{spec.version}",
    }

    uninstall_options[:user_install] = Gem.user_dir == spec.base_dir

    uninstaller = Gem::Uninstaller.new spec.name, uninstall_options

    begin
      uninstaller.uninstall
    rescue Gem::DependencyRemovalException, Gem::InstallError,
           Gem::GemNotInHomeException, Gem::FilePermissionError => e
      say "Unable to uninstall #{spec.full_name}:"
      say "\t#{e.class}: #{e.message}"
    end
  ensure
    # Restore path Gem::Uninstaller may have changed
    Gem.use_paths @original_home, *@original_path
  end

end

