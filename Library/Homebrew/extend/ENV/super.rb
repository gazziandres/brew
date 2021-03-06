require "extend/ENV/shared"
require "development_tools"

# ### Why `superenv`?
#
# 1. Only specify the environment we need (NO LDFLAGS for cmake)
# 2. Only apply compiler specific options when we are calling that compiler
# 3. Force all incpaths and libpaths into the cc instantiation (less bugs)
# 4. Cater toolchain usage to specific Xcode versions
# 5. Remove flags that we don't want or that will break builds
# 6. Simpler code
# 7. Simpler formula that *just work*
# 8. Build-system agnostic configuration of the tool-chain
module Superenv
  include SharedEnvExtension

  # @private
  attr_accessor :keg_only_deps, :deps, :run_time_deps
  attr_accessor :x11

  def self.extended(base)
    base.keg_only_deps = []
    base.deps = []
    base.run_time_deps = []
  end

  # @private
  def self.bin
  end

  def reset
    super
    # Configure scripts generated by autoconf 2.61 or later export as_nl, which
    # we use as a heuristic for running under configure
    delete("as_nl")
  end

  # @private
  def setup_build_environment(formula = nil)
    super
    send(compiler)

    self["MAKEFLAGS"] ||= "-j#{determine_make_jobs}"
    self["PATH"] = determine_path
    self["PKG_CONFIG_PATH"] = determine_pkg_config_path
    self["PKG_CONFIG_LIBDIR"] = determine_pkg_config_libdir
    self["HOMEBREW_CCCFG"] = determine_cccfg
    self["HOMEBREW_OPTIMIZATION_LEVEL"] = "Os"
    self["HOMEBREW_BREW_FILE"] = HOMEBREW_BREW_FILE.to_s
    self["HOMEBREW_PREFIX"] = HOMEBREW_PREFIX.to_s
    self["HOMEBREW_CELLAR"] = HOMEBREW_CELLAR.to_s
    self["HOMEBREW_OPT"] = "#{HOMEBREW_PREFIX}/opt"
    self["HOMEBREW_TEMP"] = HOMEBREW_TEMP.to_s
    self["HOMEBREW_OPTFLAGS"] = determine_optflags
    self["HOMEBREW_ARCHFLAGS"] = ""
    self["CMAKE_PREFIX_PATH"] = determine_cmake_prefix_path
    self["CMAKE_FRAMEWORK_PATH"] = determine_cmake_frameworks_path
    self["CMAKE_INCLUDE_PATH"] = determine_cmake_include_path
    self["CMAKE_LIBRARY_PATH"] = determine_cmake_library_path
    self["ACLOCAL_PATH"] = determine_aclocal_path
    self["M4"] = DevelopmentTools.locate("m4") if deps.any? { |d| d.name == "autoconf" }
    self["HOMEBREW_ISYSTEM_PATHS"] = determine_isystem_paths
    self["HOMEBREW_INCLUDE_PATHS"] = determine_include_paths
    self["HOMEBREW_LIBRARY_PATHS"] = determine_library_paths
    self["HOMEBREW_RPATH_PATHS"] = determine_rpath_paths(formula)
    self["HOMEBREW_DYNAMIC_LINKER"] = determine_dynamic_linker_path(formula)
    self["HOMEBREW_DEPENDENCIES"] = determine_dependencies
    self["HOMEBREW_FORMULA_PREFIX"] = formula.prefix unless formula.nil?

    # The HOMEBREW_CCCFG ENV variable is used by the ENV/cc tool to control
    # compiler flag stripping. It consists of a string of characters which act
    # as flags. Some of these flags are mutually exclusive.
    #
    # O - Enables argument refurbishing. Only active under the
    #     make/bsdmake wrappers currently.
    # x - Enable C++11 mode.
    # g - Enable "-stdlib=libc++" for clang.
    # h - Enable "-stdlib=libstdc++" for clang.
    # K - Don't strip -arch <arch>, -m32, or -m64
    # w - Pass -no_weak_imports to the linker
    #
    # On 10.8 and newer, these flags will also be present:
    # s - apply fix for sed's Unicode support
    # a - apply fix for apr-1-config path
  end
  alias generic_setup_build_environment setup_build_environment

  private

  def cc=(val)
    self["HOMEBREW_CC"] = super
  end

  def cxx=(val)
    self["HOMEBREW_CXX"] = super
  end

  def determine_cxx
    determine_cc.to_s.gsub("gcc", "g++").gsub("clang", "clang++").sub(/^cc$/, "c++")
  end

  def homebrew_extra_paths
    []
  end

  def determine_path
    path = PATH.new(Superenv.bin)

    # Formula dependencies can override standard tools.
    path.append(deps.map(&:opt_bin))
    path.append(homebrew_extra_paths)
    path.append("/usr/bin", "/bin", "/usr/sbin", "/sbin")

    # Homebrew's apple-gcc42 will be outside the PATH in superenv,
    # so xcrun may not be able to find it
    begin
      case homebrew_cc
      when "gcc-4.2"
        path.append(Formulary.factory("apple-gcc42").opt_bin)
      when GNU_GCC_REGEXP
        path.append(gcc_version_formula($&).opt_bin)
      end
    rescue FormulaUnavailableError
      # Don't fail and don't add these formulae to the path if they don't exist.
      nil
    end

    path.existing
  end

  def homebrew_extra_pkg_config_paths
    []
  end

  def determine_pkg_config_path
    PATH.new(
      deps.map { |d| d.opt_lib/"pkgconfig" },
      deps.map { |d| d.opt_share/"pkgconfig" },
    ).existing
  end

  def determine_pkg_config_libdir
    PATH.new(
      homebrew_extra_pkg_config_paths,
    ).existing
  end

  def homebrew_extra_aclocal_paths
    []
  end

  def determine_aclocal_path
    PATH.new(
      keg_only_deps.map { |d| d.opt_share/"aclocal" },
      HOMEBREW_PREFIX/"share/aclocal",
      homebrew_extra_aclocal_paths,
    ).existing
  end

  def homebrew_extra_isystem_paths
    []
  end

  def determine_isystem_paths
    PATH.new(
      HOMEBREW_PREFIX/"include",
      homebrew_extra_isystem_paths,
    ).existing
  end

  def determine_include_paths
    PATH.new(keg_only_deps.map(&:opt_include)).existing
  end

  def homebrew_extra_library_paths
    []
  end

  def determine_library_paths
    PATH.new(
      keg_only_deps.map(&:opt_lib),
      HOMEBREW_PREFIX/"lib",
      homebrew_extra_library_paths,
    ).existing
  end

  def determine_extra_rpath_paths
    []
  end

  def determine_rpath_paths(formula)
    PATH.new(
      (formula.lib unless formula.nil?),
      PATH.new(determine_extra_rpath_paths).existing,
    )
  end

  def determine_dynamic_linker_path(_formula)
    ""
  end

  def determine_dependencies
    deps.map(&:name).join(",")
  end

  def determine_cmake_prefix_path
    PATH.new(
      keg_only_deps.map(&:opt_prefix),
      HOMEBREW_PREFIX.to_s,
    ).existing
  end

  def homebrew_extra_cmake_include_paths
    []
  end

  def determine_cmake_include_path
    PATH.new(homebrew_extra_cmake_include_paths).existing
  end

  def homebrew_extra_cmake_library_paths
    []
  end

  def determine_cmake_library_path
    PATH.new(homebrew_extra_cmake_library_paths).existing
  end

  def homebrew_extra_cmake_frameworks_paths
    []
  end

  def determine_cmake_frameworks_path
    PATH.new(
      deps.map(&:opt_frameworks),
      homebrew_extra_cmake_frameworks_paths,
    ).existing
  end

  def determine_make_jobs
    if (j = self["HOMEBREW_MAKE_JOBS"].to_i) < 1
      Hardware::CPU.cores
    else
      j
    end
  end

  def determine_optflags
    if ARGV.build_bottle?
      arch = ARGV.bottle_arch || Hardware.oldest_cpu
      Hardware::CPU.optimization_flags.fetch(arch)
    elsif Hardware::CPU.intel? && !Hardware::CPU.sse4?
      Hardware::CPU.optimization_flags.fetch(Hardware.oldest_cpu)
    elsif compiler == :clang
      "-march=native"
    # This is mutated elsewhere, so return an empty string in this case
    else
      ""
    end
  end

  def determine_cccfg
    ""
  end

  public

  # Removes the MAKEFLAGS environment variable, causing make to use a single job.
  # This is useful for makefiles with race conditions.
  # When passed a block, MAKEFLAGS is removed only for the duration of the block and is restored after its completion.
  def deparallelize
    old = delete("MAKEFLAGS")
    if block_given?
      begin
        yield
      ensure
        self["MAKEFLAGS"] = old
      end
    end

    old
  end

  def make_jobs
    self["MAKEFLAGS"] =~ /-\w*j(\d+)/
    [Regexp.last_match(1).to_i, 1].max
  end

  def universal_binary
    return unless OS.mac?
    check_for_compiler_universal_support

    self["HOMEBREW_ARCHFLAGS"] = Hardware::CPU.universal_archs.as_arch_flags

    # GCC doesn't accept "-march" for a 32-bit CPU with "-arch x86_64"
    return if compiler == :clang
    return unless Hardware::CPU.is_32_bit?
    self["HOMEBREW_OPTFLAGS"] = self["HOMEBREW_OPTFLAGS"].sub(
      /-march=\S*/,
      "-Xarch_#{Hardware::CPU.arch_32_bit} \\0",
    )
  end

  def permit_arch_flags
    append "HOMEBREW_CCCFG", "K"
  end

  def m32
    append "HOMEBREW_ARCHFLAGS", "-m32"
  end

  def m64
    append "HOMEBREW_ARCHFLAGS", "-m64"
  end

  def cxx11
    if homebrew_cc == "clang"
      append "HOMEBREW_CCCFG", "x", ""
      append "HOMEBREW_CCCFG", "g", ""
    elsif gcc_with_cxx11_support?(homebrew_cc)
      append "HOMEBREW_CCCFG", "x", ""
    else
      raise "The selected compiler doesn't support C++11: #{homebrew_cc}"
    end
  end

  def libcxx
    append "HOMEBREW_CCCFG", "g", "" if compiler == :clang
  end

  def libstdcxx
    append "HOMEBREW_CCCFG", "h", "" if compiler == :clang
  end

  # @private
  def refurbish_args
    append "HOMEBREW_CCCFG", "O", ""
  end

  %w[O3 O2 O1 O0 Os].each do |opt|
    define_method opt do
      self["HOMEBREW_OPTIMIZATION_LEVEL"] = opt
    end
  end

  def set_x11_env_if_installed
  end

  def set_cpu_flags(*)
  end
end

require "extend/os/extend/ENV/super"
