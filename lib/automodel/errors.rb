require 'automodel/automodel'

module Automodel
  ## The base Error class for all {Automodel}-related issues.
  ##
  class Error < ::StandardError
  end

  ## An error resulting from an attempt to register an already-known adapter name.
  ##
  class AdapterAlreadyRegistered < Error
  end

  ## An error resulting from an attempt to automodel from an unknown adapter name.
  ##
  class UnregisteredAdapter < Error
  end

  ## An error resulting from calling #find on a table with a compound primary key.
  ##
  class CannotFindOnCompoundPrimaryKey < Error
  end
end
