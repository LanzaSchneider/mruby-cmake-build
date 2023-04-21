MRuby::Gem::Specification.new('mruby-cmake-build') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Lanza Schneider'
  spec.summary = 'CMakeLists.txt configuration generator for mruby'

  def srcfile(obj)
    src = obj.ext
    original_srcs = Dir.glob("#{"#{MRUBY_ROOT}/#{obj.relative_path_from(build.build_dir)}".ext}.c**")
    original_srcs.empty? ? "#{src}.c**" : original_srcs[0]
  end

  libmruby_core_srcs = build.libmruby_core_objs.flatten.collect{|obj|srcfile(obj)}
  libmruby_srcs = build.libmruby_objs.flatten.collect{|obj|srcfile(obj)}

  cmake_target_dir = "#{build.build_dir}/cmake"
  mkdir_p cmake_target_dir
  File.open "#{cmake_target_dir}/CMakeLists.txt", 'w' do |f|
    f << <<~EOF
    cmake_minimum_required(VERSION 3.3)
    project(mruby)
    EOF

    f << <<~EOF
    file(GLOB MRB_HEADERS #{build.build_dir}/include/*)
    file(COPY ${MRB_HEADERS} DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/include)
    file(RENAME ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.origin.h)
    EOF
    build.cc.defines.each do |define|
      f.puts "file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h \"#define #{define}\\n\")"
    end
    f.puts 'file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/include/mrbconf.h "#include \\"mrbconf.origin.h\\"\\n")'

    f.puts "set(MRB_CORE_SOURCES "")"
    libmruby_core_srcs.flatten.each do |src|
      if src.end_with?('*')
        f.puts "file(GLOB MRB_CORE_SOURCE #{src})"
        f.puts "set(MRB_CORE_SOURCES ${MRB_CORE_SOURCES};${MRB_CORE_SOURCE})"
      else
        f.puts "set(MRB_CORE_SOURCES ${MRB_CORE_SOURCES};#{src})"
      end
    end

    f << <<~EOF
    add_library(mruby_core STATIC ${MRB_CORE_SOURCES})
    include_directories(${CMAKE_CURRENT_BINARY_DIR}/include)
    EOF

    f.puts "set(MRB_SOURCES "")"
    libmruby_srcs.flatten.each do |src|
      if src.end_with?('*')
        f.puts "file(GLOB MRB_SOURCE #{src})"
        f.puts "set(MRB_SOURCES ${MRB_SOURCES};${MRB_SOURCE})"
      else
        f.puts "set(MRB_SOURCES ${MRB_SOURCES};#{src})"
      end
    end

    f << <<~EOF
    add_library(mruby STATIC ${MRB_SOURCES})
    include_directories(${CMAKE_CURRENT_BINARY_DIR}/include)
    EOF
  end
end