bin_conf = configuration_data()
bin_conf.set('pkgdatadir', pkgdatadir)

install_data('gdbus_ext.rb', install_dir: pkgdatadir)
install_data('ruby-previewer.rb', install_dir: pkgdatadir)

configure_file(
  input: 'workbench-ruby-previewer',
  output: 'workbench-ruby-previewer',
  configuration: bin_conf,
  install: true,
  install_dir: get_option('bindir')
)
