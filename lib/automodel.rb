require 'active_record'
require 'active_support/all'
require 'securerandom'

require 'automodel/automodel'
require 'automodel/connectors'
require 'automodel/schema_inspector'
require 'automodel/version'

## The main (really *only*) entrypoint for the Automodel gem. This is the method the end-user calls
## to trigger a database scrape and model generation.
##
##
## @param spec [Symbol, String, Hash]
##   The Symbol/String/Hash to pass through to the ActiveRecord connection resolver, as detailed in
##   [ActiveRecord::ConnectionHandling#establish_connection](http://bit.ly/2JQdA8c). Whether the
##   given `spec` value is a Hash or is a Symbol/String to run through the ActiveRecord resolver,
##   the resulting Hash may include the following options (in addition to the actual connection
##   parameters).
##
## @option spec [String] :subschema
##   The name of an additional namespace with which tables in the target database are prefixed.
##   Intended for use with SQL Server, where tables' fully-qualified names may have an additional
##   namespace between the database name and the table name (e.g. `database.dbo.table`, in which
##   case the subschema would be `"dbo"`.
##
## @option spec [String] :namespace
##   A String representing the desired namespace for the generated model classes (e.g. `"NewDB"` or
##   `"WeirdDB::Models"`). If not given, the generated models will fall under `Kernel` so they are
##   always available without namespacing, like standard user-defined model classes.
##
##
## @return [ActiveRecord::Base]
##   The returned value is an instance of an ActiveRecord::Base subclass. This is the class that
##   serves as superclass to all of the generated model classes, so that a list of all models can be
##   easily compiled by calling `#subclasses` on this value.
##
def automodel(spec)
  ## Build out a connection spec Hash from the given value.
  ##
  resolver = ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver
  connection_spec = resolver.new(ActiveRecord::Base.configurations).resolve(spec).symbolize_keys

  ## We need a base class for all of the models we're about to create, but don't want to pollute
  ## ActiveRecord::Base's own connection pool, so we'll need a subclass. This will serve as both
  ## our base class for new models and as the connection pool handler. We're defining it with names
  ## that reflect both uses just to keep the code more legible.
  ##
  base_class_for_new_models = connection_handler = Class.new(ActiveRecord::Base)
  register_class(connection_handler, as: "Connector_#{SecureRandom.uuid.delete('-')}",
                                     within: :'Automodel::Connectors')

  ## Establish a connection with the given params.
  ##
  connection_handler.establish_connection(connection_spec)

  ## Map out the table structures.
  ##
  tables = map_tables(connection_handler, subschema: connection_spec.fetch(:subschema, ''))

  ## Define the table models.
  ##
  tables.each do |table|
    table[:model] = Class.new(base_class_for_new_models) do
      ## We can't assume table properties confom to any standard.
      ##
      self.table_name = table[:name]
      self.primary_key = table[:primary_key]

      ## Don't allow `#find` for tables with a composite primary key.
      ##
      def find(*args)
        raise Automodel::CannotFindOnCompoundPrimaryKey if table[:composite_primary_key]
        super
      end

      ## Create railsy column name aliases whenever possible.
      ##
      table[:columns].each do |column|
        railsy_name = railsy_column_name(column)
        unless table[:column_aliases].key? railsy_name
          table[:column_aliases][railsy_name] = column
          alias_attribute(railsy_name, column.name)
        end
      end
    end

    ## Register the model class.
    ##
    register_class(table[:model], as: table[:model_name],
                                  within: connection_spec.fetch(:namespace, :Kernel))
  end

  ## With all models registered, we can safely declare relationships.
  ##
  tables.map { |table| table[:foreign_keys] }.flatten.each do |fk|
    from_table = tables.find { |table| table[:name].split('.').last == fk.from_table }
    next unless from_table.present?

    to_table = tables.find { |table| table[:name].split('.').last == fk.to_table }
    next unless to_table.present?

    association_setup = <<~END_OF_HEREDOC
      belongs_to #{to_table[:base_name].to_sym.inspect},
                 class_name: #{to_table[:model].to_s.inspect},
                 primary_key: #{fk.options[:primary_key].to_sym.inspect},
                 foreign_key: #{fk.options[:column].to_sym.inspect}

      alias #{to_table[:model_name].underscore.to_sym.inspect} #{to_table[:base_name].to_sym.inspect}
    END_OF_HEREDOC
    from_table[:model].class_eval(association_setup, __FILE__, __LINE__)
  end

  ## There's no obvious value we can return that would be of any use, except maybe the base class,
  ## in case the end user wants to procure a list of all the models (via `#subclasses`).
  ##
  base_class_for_new_models
end

## Takes a connection pool (an object that implements ActiveRecord::ConnectionHandling), scrapes the
## target database, and returns a list of the tables' metadata.
##
##
## @param connection_handler [ActiveRecord::ConnectionHandling]
##   The connection pool/handler to inspect and map out.
##
## @param subschema [String]
##   The name of an additional namespace with which tables in the target database are prefixed, as
##   eplained in {#automodel}.
##
##
## @return [Array<Hash>]
##   An Array where each value is a Hash representing a table in the target database. Each such Hash
##   will define the following keys:
##
##   - `:name` [String] -- The table name, prefixed with the subschema name (if one is given).
##   - `:columns` [Array<ActiveRecord::ConnectionAdapters::Column>] -- A list columns im the table.
##   - `:primary_key` [String, Array<String>] -- The primary key. (An Array for composite keys.)
##   - `:foreign_keys` [Array<ActiveRecord::ConnectionAdapters::ForeignKeyDefinition>] -- The FKs.
##   - `:base_name` [String] -- The table name, with no subschema.
##   - `:model_name` [String] -- A Railsy class name for the corresponding model.
##   - `:composite_primary_key` [true, false] -- Whether this table has a composite primary key.
##   - `:column_aliases` [Hash<String, ActiveRecord::ConnectionAdapters::Column>]-- Maps column names to their definition.
##
def map_tables(connection_handler, subschema: '')
  ## Normalize the "subschema" name.
  ##
  subschema = "#{subschema}.".sub(%r{\.+$}, '.').sub(%r{^\.}, '')

  ## Prep the Automodel::SchemaInspector we'll be using.
  ##
  schema_inspector = Automodel::SchemaInspector.new(connection_handler)

  ## Get as much metadata as possible out of the Automodel::SchemaInspector.
  ##
  schema_inspector.tables.map do |table_name|
    table = {}

    table[:name] = "#{subschema}#{table_name}"
    table[:columns] = schema_inspector.columns(table[:name])
    table[:primary_key] = schema_inspector.primary_key(table[:name])
    table[:foreign_keys] = schema_inspector.foreign_keys(table[:name])

    table[:base_name] = table[:name].split('.').last
    table[:model_name] = table[:base_name].underscore.classify
    table[:composite_primary_key] = table[:primary_key].is_a? Array
    table[:column_aliases] = table[:columns].map { |column| [column.name, column] }.to_h

    table
  end
end

## Returns a Railsy name for the given column.
##
##
## @param column [ActiveRecord::ConnectionAdapters::Column]
##   The column for which we want to generate a Railsy name.
##
##
## @return [String]
##   The given column's name, in Railsy form. Note Date/Datetime columns are not suffixed with "_on"
##   or "_at" per Rails norm, as this can work against you with column names like "BirthDate" (which
##   would turn into "birth_on"). A future release will address this by building out a comprehensive
##   list of such names and their correct Railsy representation, but that is not currently the case.
##
def railsy_column_name(column)
  case column.type
  when :boolean
    column.name.underscore.sub(%r{^is_}, '')
  else
    column.name.underscore
  end
end

## Registers the given class "as" the given name and "within" the given namespace (if any).
##
##
## @param class_object [Class]
##   The class to register.
##
## @param as [String]
##   The name with which to register the class. Note this should be a base name (no "::").
##
## @param within [String, Symbol, Module, Class]
##   The module/class under which the given class should be registered. If the named module/class
##   does not exist, as many nested modules as needed are declared so the class can be registered
##   as requested.
##
##   e.g.: `register_class(Class.new, as: "Sample", within: "Many::Levels::Deep")` will declare
##         module `Many`, module `Many::Levels`, module `Many::Levels::Deep`, and then register
##         the given class as `Many::Levels::Deep::Sample`.
##
##
## @return [Class]
##   The newly-registered class (the same value as the originally-submitted "class_object").
##
def register_class(class_object, as:, within: :Kernel)
  components = within.to_s.split('::').compact.map(&:to_sym)
  components.unshift(:Kernel) unless components.first.to_s.safe_constantize.present?

  namespace = components.shift.to_s.constantize
  components.each do |component|
    namespace = if component.in? namespace.constants
                  namespace.const_get(component)
                else
                  namespace.const_set(component, Module.new)
                end
  end

  namespace.const_set(as, class_object)
end
