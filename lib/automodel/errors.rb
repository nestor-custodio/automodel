require 'automodel/automodel'

module Automodel
  ## The base Error class for all **automodel** gem issues.
  ##
  class Error < ::StandardError
  end

  ## An error resulting from an attempt to register the same adapter name with
  ## {Automodel::SchemaInspector.register_adapter} multiple times.
  ##
  class AdapterAlreadyRegisteredError < Error
  end

  ## An error resulting from an aborted Automodel due to a class name collision.
  ##
  class NameCollisionError < Error
  end

  ## An error resulting from calling `#find` on a table with a compound primary key.
  ##
  class FindOnCompoundPrimaryKeyError < Error
  end
end
