require 'spec_helper'

def set_file_content(string)
	string = normalize_string_indent(string)
	File.open(filename, 'w'){ |f| f.write(string) }
	vim.edit filename
end

def get_file_content()
	vim.write
	IO.read(filename).strip
end

def before(string)
	set_file_content(string)
end

def after(string)
	expect(get_file_content()).to eq normalize_string_indent(string)
end

def type(string)
	string.scan(/<.*?>|./).each do |key|
		if /<.*>/.match(key)
			vim.feedkeys "\\#{key}"
		else
			vim.feedkeys key
		end
	end
end

def execute(string)
	vim.command(string)
end

describe "Testing expand tags on multiple line" do
	let(:filename) { 'test.txt' }

	specify "- Single line in normal mode" do
		before <<-EOF
			<a href="#">bla bla bla</a>
		EOF

		type '<C-m>'

		after <<-EOF
			<a href="#">
				bla bla bla
			</a>
		EOF
	end

	specify "- Single line in visual mode" do
		before <<-EOF
			<a href="#">bla bla bla</a>
		EOF

		type 'V<C-m>'

		after <<-EOF
			<a href="#">
				bla bla bla
			</a>
		EOF
	end

	specify "- Indent keeping in normal mode" do
		before <<-EOF
			bla bla bla
				<a href="#">bla bla bla</a>
		EOF

		type 'j<C-m>'

		after <<-EOF
			bla bla bla
				<a href="#">
					bla bla bla
				</a>
		EOF
	end


	specify "- Indent keeping in visual mode" do
		before <<-EOF
			bla bla bla
				<a href="#">bla bla bla</a>
		EOF

		type 'jV<C-m>'

		after <<-EOF
			bla bla bla
				<a href="#">
					bla bla bla
				</a>
		EOF
	end

	specify "- Indent keeping when indentation is not selected" do
		before <<-EOF
			bla bla bla
				<a href="#">bla bla bla</a>
		EOF

		type 'jvat<C-m>'

		after <<-EOF
			bla bla bla
				<a href="#">
					bla bla bla
				</a>
		EOF
	end

	specify "- Tag with content before and after" do
		before <<-EOF
			bla bla bla
				bla<a href="#">bla bla bla</a>bla
		EOF

		type 'j^3lvat<C-m>'

		after <<-EOF
			bla bla bla
				bla
				<a href="#">
					bla bla bla
				</a>
				bla
		EOF
	end

	specify "- Tag surrounds with empty lines" do
		before <<-EOF
			bla bla bla

			<a href="#">bla bla bla</a>

			bla bla bla
		EOF

		type 'jV3j<C-m>'

		after <<-EOF
			bla bla bla

			<a href="#">
				bla bla bla
			</a>

			bla bla bla
		EOF
	end

	specify "- Spaces between two tags" do
		before <<-EOF
			<ul> <a href="#">bla bla bla</a> </ul>
		EOF

		type '<C-m>'

		after <<-EOF
			<ul>
				<a href="#">
					bla bla bla
				</a>
			</ul>
		EOF
	end

	specify "- Spaces in tags content" do
		before <<-EOF
			<ul> <a href="#">  bla bla bla  </a> </ul>
		EOF

		type '<C-m>'

		after <<-EOF
			<ul>
				<a href="#">
					bla bla bla
				</a>
			</ul>
		EOF
	end

	specify "- With php tag" do
		before <<-EOF
			<a href="<?= $href ?>">bla bla bla</a>
		EOF

		type '<C-m>'

		after <<-EOF
			<a href="<?= $href ?>">
				bla bla bla
			</a>
		EOF
	end
end
