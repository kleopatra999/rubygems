require 'rubygems/test_case'
require 'rubygems/request_set'
require 'rubygems/request_set/lockfile'

class TestGemRequestSetLockfile < Gem::TestCase

  def setup
    super

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    util_set_arch 'i686-darwin8.10.1'

    @set = Gem::RequestSet.new

    @vendor_set = Gem::DependencyResolver::VendorSet.new

    @set.instance_variable_set :@vendor_set, @vendor_set

    @gem_deps_file = 'gem.deps.rb'

    @lockfile = Gem::RequestSet::Lockfile.new @set, @gem_deps_file
  end

  def spec_fetcher
    gems = {}

    gem_maker = Object.new
    gem_maker.instance_variable_set :@test,  self
    gem_maker.instance_variable_set :@gems,  gems

    def gem_maker.gem name, version, dependencies = nil, &block
      spec, gem = @test.util_gem name, version, dependencies, &block

      @gems[spec] = gem

      spec
    end

    yield gem_maker

    util_setup_spec_fetcher *gems.keys

    gems.each do |spec, gem|
      @fetcher.data["http://gems.example.com/gems/#{spec.file_name}"] =
        Gem.read_binary(gem)
    end
  end

  def write_gem_deps gem_deps
    open @gem_deps_file, 'w' do |io|
      io.write gem_deps
    end
  end

  def write_lockfile lockfile
    open "#{@gem_deps_file}.lock", 'w' do |io|
      io.write lockfile
    end
  end

  def test_token_pos
    assert_equal [5, 0], @lockfile.token_pos(5)

    @lockfile.instance_variable_set :@line_pos, 2
    @lockfile.instance_variable_set :@line, 1

    assert_equal [3, 1], @lockfile.token_pos(5)
  end

  def test_tokenize
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    expected = [
      [:section, 'GEM',                0, 0],
      [:newline, nil,                  3, 0],
      [:entry,   'remote',             2, 1],
      [:text,    @gem_repo,           10, 1],
      [:newline, nil,                 34, 1],
      [:entry,   'specs',              2, 2],
      [:newline, nil,                  8, 2],
      [:text,    'a',                  4, 3],
      [:l_paren, nil,                  6, 3],
      [:text,    '2',                  7, 3],
      [:r_paren, nil,                  8, 3],
      [:newline, nil,                  9, 3],
      [:newline, nil,                  0, 4],
      [:section, 'PLATFORMS',          0, 5],
      [:newline, nil,                  9, 5],
      [:text,    Gem::Platform::RUBY,  2, 6],
      [:newline, nil,                  6, 6],
      [:newline, nil,                  0, 7],
      [:section, 'DEPENDENCIES',       0, 8],
      [:newline, nil,                 12, 8],
      [:text,    'a',                  2, 9],
      [:newline, nil,                  3, 9],
    ]

    assert_equal expected, @lockfile.tokenize
  end

  def test_to_s_gem
    spec_fetcher do |s|
      s.gem 'a', 2
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_dependency
    spec_fetcher do |s|
      s.gem 'a', 2, 'c' => '>= 0', 'b' => '>= 0'
      s.gem 'b', 2
      s.gem 'c', 2
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b
      c
    b (2)
    c (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_dependency_non_default
    spec_fetcher do |s|
      s.gem 'a', 2, 'b' => '>= 1'
      s.gem 'b', 2
    end

    @set.gem 'b'
    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (>= 1)
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
  b
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_dependency_requirement
    spec_fetcher do |s|
      s.gem 'a', 2, 'b' => '>= 0'
      s.gem 'b', 2
    end

    @set.gem 'a', '>= 1'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a (>= 1)
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_path
    name, version, directory = vendor_gem

    @vendor_set.add_vendor_gem name, directory

    @set.gem 'a'

    expected = <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    #{name} (#{version})

GEM

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a!
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_path_absolute
    name, version, directory = vendor_gem

    @vendor_set.add_vendor_gem name, File.expand_path(directory)

    @set.gem 'a'

    expected = <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    #{name} (#{version})

GEM

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a!
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

  def test_to_s_gem_platform
    spec_fetcher do |s|
      s.gem 'a', 2 do |spec|
        spec.platform = Gem::Platform.local
      end
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2-#{Gem::Platform.local})

PLATFORMS
  #{Gem::Platform.local}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, @lockfile.to_s
  end

end
