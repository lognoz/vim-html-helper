require 'vimrunner'
require 'vimrunner/rspec'

Vimrunner::RSpec.configure do |config|
	config.reuse_server = true
	plugin_path = File.expand_path('../..', __FILE__)

	config.start_vim do
		vim = Vimrunner.start_gvim
		vim.command('let g:markup_language_expand = \'<C-m>\'')
		vim.add_plugin(plugin_path, 'plugin/markup_language.vim')
		vim
	end
end
