$:.unshift File.dirname(__FILE__) # For use/testing when no gem is installed

# Require all of the Ruby files in the given directory.
#
# path - The String relative path from here to the directory.
#
# Returns nothing.
def require_all_in(path)
  glob = File.join(File.dirname(__FILE__), path, '*.rb')
  Dir[glob].each do |f|
    require f
  end
end

require 'eventmachine'
require 'yajl'
require 'html_press'
require 'github/markdown'
require 'github/markup'
require 'jekyll'
require 'thin'

require 'mysite_server/site'
require 'mysite_server/datasource'
require_all_in 'mysite_server/datasources'

module MySite_Server
  VERSION = '0.11.2'
  
  DEFAULTS = {
    "GitHub" => {
      "user" => ENV["GITHUB_USER"],
      "org"  => ENV["GITHUB_ORG"]
    }
    
  }

  def self.configuration(override)
    # Merge Jekyll::DEFAULTS < _config.yml < MySite_Server::DEFAULTS < override
    override = MySite_Server::DEFAULTS.deep_merge(override)
    Jekyll.configuration(override)
  end
end