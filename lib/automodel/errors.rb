require 'automodel/automodel'

module Automodel
  ## The base Error class for all **automodel** gem issues.
  ##
  class Error < ::StandardError
  end

  ## An error resulting from an attempt to register the same adapter name with
  ## {Automodel::SchemaInspector.register_adapter} multiple times.
  ##
  class AdapterAlreadyRegistered < Error
  end

  ## An error resulting from calling `#find` on a table with a compound primary key.
  ##
  class CannotFindOnCompoundPrimaryKey < Error
  end
end
