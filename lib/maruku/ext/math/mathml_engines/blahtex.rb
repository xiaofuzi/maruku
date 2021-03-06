require 'tempfile'
require 'fileutils'
require 'digest/md5'
require 'pstore'
require 'nokogiri'

module MaRuKu::Out::HTML
  PNG = Struct.new(:src, :depth, :height)

  def convert_to_png_blahtex(kind, tex)
    FileUtils.mkdir_p get_setting(:html_png_dir)

    # first, we check whether this image has already been processed
    md5sum = Digest::MD5.hexdigest(tex + " params: ")
    result_file = File.join(get_setting(:html_png_dir), md5sum + ".txt")

    unless File.exists?(result_file)
      Tempfile.open('maruku_blahtex') do |tmp_in|
        tmp_in.write tex
        tmp_in.close

        # It's important taht we don't replace *all* newlines,
        # because newlines in arguments get escaped as "'\n'".
        system <<COMMAND.gsub("\n  ", " ")
blahtex --png --use-preview-package
  --shell-dvipng #{Shellwords.shellescape("dvipng -D #{Shellwords.shellescape(get_setting(:html_png_resolution).to_s)}")}
  #{'--displaymath' if kind == :equation}
  --temp-directory #{Shellwords.shellescape(get_setting(:html_png_dir))}
  --png-directory #{Shellwords.shellescape(get_setting(:html_png_dir))}
  < #{Shellwords.shellescape(tmp_in.path)}
  > #{Shellwords.shellescape(result_file)}
COMMAND
      end
    end

    result = File.read(result_file)
    if result.nil? || result.empty?
      maruku_error "Blahtex error: empty output"
      return
    end

    doc = Nokogiri::XML::Document.parse(result)
    png = doc.root.elements.to_a.first
    if png.name != 'png'
      maruku_error "Blahtex error: \n#{doc}"
      return
    end

    raise "No depth element in:\n #{doc}" unless depth = png.xpath('//depth')[0]
    raise "No height element in:\n #{doc}" unless height = png.xpath('//height')[0]
    raise "No md5 element in:\n #{doc}" unless md5 = png.xpath('//md5')[0]

    depth = depth.text.to_f
    height = height.text.to_f # TODO: check != 0
    md5 = md5.text

    PNG.new("#{get_setting(:html_png_url)}#{md5}.png", depth, height)
  rescue x=> e
    maruku_error "Error: #{e}"
  end

  def convert_to_mathml_blahtex(kind, tex)
    @@BlahtexCache ||= PStore.new(get_setting(:latex_cache_file))

    @@BlahtexCache.transaction do
      if @@BlahtexCache[tex].nil?
        Tempfile.open('maruku_blahtex') do |tmp_in|
          tmp_in.write tex

          Tempfile.new('maruku_blahtex') do |tmp_out|
            system "blahtex --mathml < #{Shellwords.shellescape(tmp_in.path)} > #{Shellwords.shellescape(tmp_out.path)}"
            @@BlahtexCache[tex] = tmp_out.read
          end
        end
      end

      blahtex = @@BlahtexCache[tex]
      doc = Nokogiri::XML::Document.parse(result)
      unless mathml = doc.css('mathml').first
        maruku_error "Blahtex error: \n#{doc}"
        return
      end

      return mathml
    end
  rescue => e
    maruku_error "Error: #{e}"
  end
end
