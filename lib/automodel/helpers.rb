require 'automodel/automodel'
require 'automodel/schema_inspector'

module Automodel
  ## Houses some helper methods used directly by {::automodel}.
  ##
  module Helpers
    class << self
      ## Takes a connection handler (an object that implements ActiveRecord::ConnectionHandling),
      ## scrapes the target database, and returns a list of the tables' metadata.
      ##
      ##
      ## @param connection_handler [ActiveRecord::ConnectionHandling]
      ##   The connection pool/handler to inspect and map out.
      ##
      ## @param subschema [String]
      ##   The name of an additional namespace with which tables in the target database are
      ##   prefixed, as eplained in {::automodel}.
      ##
      ##
      ## @return [Array<Hash>]
      ##   An Array where each value is a Hash representing a table in the target database. Each
      ##   such Hash will define the following keys:
      ##
      ##   - `:name` (String) -- The table name, prefixed with the subschema name (if one is given).
      ##   - `:columns` (Array<ActiveRecord::ConnectionAdapters::Column>)
      ##   - `:primary_key` (String, Array<String>)
      ##   - `:foreign_keys` (Array<ActiveRecord::ConnectionAdapters::ForeignKeyDefinition>)
      ##   - `:base_name` (String) -- The table name, with no subschema.
      ##   - `:model_name` (String) -- A Railsy class name for the corresponding model.
      ##   - `:composite_primary_key` (true, false)
      ##   - `:column_aliases` (Hash<String, ActiveRecord::ConnectionAdapters::Column>)
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
      ##   The given column's name, in Railsy form.
      ##
      ##   Note Date/Datetime columns are not suffixed with "_on" or "_at" per Rails norm, as this
      ##   can work against you sometimes ("BirthDate" turns into "birth_on"). A future release will
      ##   address this by building out a comprehensive list of such names and their correct Railsy
      ##   representation, but that is not currently the case.
      ##
      def railsy_column_name(column)
        name = railsy_name(column.name)
        name = name.sub(%r{^is_}, '') if column.type == :boolean

        name
      end

      ## Returns the given name in Railsy form.
      ##
      ##
      ## @param name [String, Symbol]
      ##   The column name for which we want to generate a Railsy name.
      ##
      ##
      ## @return [String]
      ##   The given name, in Railsy form.
      ##
      def railsy_name(name)
        name.to_s.gsub(%r{[^a-z0-9]+}i, '_').underscore
      end

      ## Registers the given class **as** the given name and **within** the given namespace (if any).
      ##
      ##
      ## @param class_object [Class]
      ##   The class to register.
      ##
      ## @param as [String]
      ##   The name with which to register the class. Note this should be a base name (no "::").
      ##
      ## @param within [String, Symbol, Module, Class]
      ##   The module/class under which the given class should be registered. If the named module or
      ##   class does not exist, as many nested modules as needed are declared so the class can be
      ##   registered as requested.
      ##
      ##   e.g. Calling this method with an "as" value of `"Sample"` and a "within" value of
      ##        `"Many::Levels::Deep"` will: check for module/class "Many" and create one as a
      ##        Module if it doesn't already exist; then check for a module/class "Many::Levels" and
      ##        create a "Levels" Module within `Many` if it doesn't already exist; then check for a
      ##        module/class "Many::Levels::Deep" and create a "Deep" Module within `Many::Levels`
      ##        if it doesn't already exist; and finally register the given class as "Sample" within
      ##        `Many::Levels::Deep`.
      ##
      ##
      ## @return [Class]
      ##   The newly-registered class (the same value as the originally-submitted "class_object").
      ##
      def register_class(class_object, as:, within: nil)
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
    end
  end
end
