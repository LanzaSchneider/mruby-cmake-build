MRuby::Gem::Specification.new('mruby-cmake-build') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Lanza Schneider'
  spec.summary = 'CMakeLists.txt configuration generator for mruby'

  # source filepath detector
  def srcfile obj
    src = obj.ext
    original_srcs = Dir.glob("#{"#{MRUBY_ROOT}/#{obj.relative_path_from(build.build_dir)}".ext}.c**")
    original_srcs.empty? ? "#{src}.c**" : original_srcs[0]
  end

  # setup all mrbgems
  build.gems.each(&:setup)
  gems = build.gems.check(build)

  # prebuilt sources
  libmruby_core_srcs = build.libmruby_core_objs.flatten.collect{|obj|srcfile(obj)}
  libmruby_core_srcs.uniq!
  libmruby_srcs = build.libmruby_objs.flatten.collect{|obj|srcfile(obj)}
  gems.each do |gem|
    next if gem.objs.nil?
    gem_real_dir = gem.dir
    libmruby_srcs += gem.objs.flatten.collect{|obj|srcfile(obj)}
    libmruby_srcs += gem.objs.flatten.collect{|obj|srcfile(obj.sub(gem.build_dir, gem_real_dir))}
  end
  libmruby_srcs << "#{build.build_dir}/mrbgems/gem_init.c"
  libmruby_srcs.uniq!

  # cmakelists prepare
  cmake_target_dir = "#{build.build_dir}/cmake"
  mkdir_p cmake_target_dir

  # parse mrbconf.h
  mrbconf_options = {}
  File.open "#{MRUBY_ROOT}/include/mrbconf.h", 'r' do |f|
    tip = ''
    last_line_define = nil
    while !f.eof?
      line = f.readline.strip
      if line.empty? || (line.include?('#') && !line.include?('#define'))
        tip = ''
        last_line_define = nil
        next
      elsif line.include?('#define')
        if tip.strip.empty? && last_line_define.nil?
          tip = ''
          last_line_define = nil
          next
        end
        option = line.split('#define ')[1].split(' ')
        default = nil
        if option[1] && !(option[1].include?('*') || option[1].include?('//'))
          default = option[1]
        end
        mrbconf_options[option[0]] = 
        {
          :tip => tip,
          :default => default,
        }
        last_line_define = line
        next
      end
      tip << "#{line.sub('/*', '').sub('*/', '').strip}\\n"
      last_line_define = nil
    end
  end

  # cmakelists generation
  File.open "#{cmake_target_dir}/CMakeLists.txt", 'w' do |f|
    f << <<~EOF
    cmake_minimum_required(VERSION 3.3)
    project(mruby)
    EOF

    # build mrbconf.h
    f << <<~EOF
    file(GLOB MRB_HEADERS #{MRUBY_ROOT}/include/*)
    file(COPY ${MRB_HEADERS} DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/include)
    file(GLOB MRB_HEADERS #{build.build_dir}/include/*)
    file(COPY ${MRB_HEADERS} DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/include)
    file(RENAME ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.origin.h)
    EOF
    mrbconf_defines = []
    mrbconf_defines += build.defines
    gems.each do |gem|
      gem.compilers.each do |compiler|
        next if compiler.nil?
        mrbconf_defines += compiler.defines
      end
    end
    mrbconf_options.each_pair do |define, args|
      if args[:default]
        f << <<~EOF
        set(#{define} "#{args[:default]}" CACHE STRING "#{args[:tip]}" FORCE)
        file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h \"#define #{define} ${#{define}}\\n\")
        EOF
      else
        f << <<~EOF
        option(#{define} "#{args[:tip]}" OFF)
        if (#{define})
          file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h \"#define #{define}\\n\")
        endif()
        EOF
      end
    end
    mrbconf_defines.uniq.each do |define|
      f.puts "file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h \"#define #{define.sub('=', ' ')}\\n\")"
    end
    f.puts 'file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h "#include \\"mrbconf.origin.h\\"\\n")'

    # build libmruby_core
    f.puts "set(SOURCES "")"
    libmruby_core_srcs.flatten.each do |src|
      if src.end_with?('*')
        f.puts "file(GLOB SOURCE #{src})"
        f.puts "set(SOURCES ${SOURCES};${SOURCE})"
      else
        f.puts "set(SOURCES ${SOURCES};#{src})"
      end
    end
    f.puts "set(MRB_CORE_SOURCES ${SOURCES} CACHE STRING \"libmruby_core sources\" FORCE)"
    f.puts "add_library(mruby_core STATIC ${MRB_CORE_SOURCES})"
	f.puts "set_property(TARGET mruby_core PROPERTY POSITION_INDEPENDENT_CODE ON)"

    # build libmruby
    f.puts "set(SOURCES "")"
    libmruby_srcs.flatten.each do |src|
      if src.end_with?('*')
        f.puts "file(GLOB SOURCE #{src})"
        f.puts "set(SOURCES ${SOURCES};${SOURCE})"
      else
        f.puts "set(SOURCES ${SOURCES};#{src})"
      end
    end
    f.puts "set(MRB_SOURCES ${SOURCES} CACHE STRING \"libmruby sources\" FORCE)"
    f.puts "add_library(mruby STATIC ${MRB_SOURCES})"
	  f.puts "set_property(TARGET mruby PROPERTY POSITION_INDEPENDENT_CODE ON)"

    # give include
    f.puts "target_include_directories(mruby_core PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>)"
    f.puts "target_include_directories(mruby PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>)"
    gems.each do |gem|
      next if gem.export_include_paths.nil?
      gem.export_include_paths.flatten.each do |include_path|
        f.puts "target_include_directories(mruby PUBLIC $<BUILD_INTERFACE:#{include_path}>)"
      end
    end
  end
end
