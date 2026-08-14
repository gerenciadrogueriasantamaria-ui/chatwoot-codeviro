# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/

require 'down'
require 'tempfile'

class Whatsapp::IncomingMessageWhatsappCloudService < Whatsapp::IncomingMessageBaseService
  private

  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  def download_attachment_file(attachment_payload)
    url_response = HTTParty.get(
      inbox.channel.media_url(attachment_payload[:id]),
      headers: inbox.channel.api_headers
    )

    inbox.channel.authorization_error! if url_response.unauthorized?
    return unless url_response.success?

    media_url = url_response.parsed_response['url']
    return if media_url.blank?

    download_media_file(media_url, attachment_payload)
  end

  def download_media_file(media_url, attachment_payload)
    downloaded_file = Down.download(
      media_url,
      headers: media_download_headers,
      max_size: attachment_size_limit
    )

    normalize_downloaded_file(downloaded_file, attachment_payload)
  rescue Down::Error => e
    Rails.logger.error("[WhatsApp Cloud] Failed to download media #{attachment_payload[:id]}: #{e.class} - #{e.message}")
    nil
  end

  def normalize_downloaded_file(downloaded_file, attachment_payload)
    mime_type = attachment_payload[:mime_type].presence ||
                attachment_payload['mime_type'].presence ||
                downloaded_file.content_type.presence ||
                'application/octet-stream'

    filename = attachment_payload[:filename].presence ||
               attachment_payload['filename'].presence ||
               downloaded_file.original_filename.presence ||
               "#{attachment_payload[:id]}.#{extension_from_content_type(mime_type)}"

    normalized_file = Tempfile.new(['whatsapp-cloud-media', File.extname(filename)])
    normalized_file.binmode
    downloaded_file.rewind
    IO.copy_stream(downloaded_file, normalized_file)
    normalized_file.rewind

    normalized_file.define_singleton_method(:original_filename) { filename }
    normalized_file.define_singleton_method(:content_type) { mime_type }

    normalized_file
  end

  def media_download_headers
    inbox.channel.api_headers.except('Content-Type')
  end

  def attachment_size_limit
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit_mb = 40 if limit_mb <= 0

    limit_mb.megabytes
  end

  def extension_from_content_type(content_type)
    case content_type.to_s
    when /image\/jpeg/
      'jpg'
    when /image\/png/
      'png'
    when /image\/webp/
      'webp'
    when /image\/gif/
      'gif'
    when /audio\/ogg/
      'ogg'
    when /audio\/mpeg/
      'mp3'
    when /audio\/mp4/
      'm4a'
    when /audio\/amr/
      'amr'
    when /audio\/webm/
      'webm'
    when /video\/mp4/
      'mp4'
    when /application\/pdf/
      'pdf'
    else
      'bin'
    end
  end
end
