# mruby-cmake-build

CMakeLists.txt configuration generator for mruby.

## install by mrbgems

MRuby::Build.new do |conf| # or CrossBuild
  conf.gem :github => 'LanzaSchneider/mruby-cmake-build'
end

After build, you can found CMakeLists.txt in ```MRUBY_ROOT/build/${build_name}/cmake``` .
