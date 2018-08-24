require 'vimrunner'
require 'vimrunner/rspec'

Vimrunner::RSpec.configure do |config|
	plugin_path = File.expand_path('../..', __FILE__)

	config.reuse_server = false
	config.start_vim do
		vim = Vimrunner.start_gvim
		vim.add_plugin(plugin_path, 'plugin/html_helper.vim')
		vim
	end
end
