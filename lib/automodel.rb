require 'active_record'
require 'active_support/all'
require 'securerandom'

require 'automodel/automodel'
require 'automodel/connectors'
require 'automodel/schema_inspector'
require 'automodel/version'

def automodel(*args)
  ## Build out a connection spec Hash from the given `*args`.
  ##
  resolver = ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver
  connection_spec = resolver.new(ActiveRecord::Base.configurations).resolve(*args).symbolize_keys

  ## We need a base class for all of the models we're about to create, but don't want to pollute
  ## ActiveRecord::Base's own connection pool, so we'll need a subclass. This will serve as both
  ## our base class for new models and as the connection pool handler. Am defining it with names
  ## that reflect both uses just to keep the code more legible.
  ##
  base_class_for_new_models = connection_handler = Class.new(ActiveRecord::Base)
  register_class(connection_handler, as: "Connector_#{SecureRandom.uuid.delete('-')}",
                                     within: :'Automodel::Connectors')

  ## Establish a connection with the given params.
  ##
  connection_handler.establish_connection(connection_spec)

  ## Build the base table map.
  ##
  tables = map_tables(connection_handler, subschema: connection_spec.fetch(:subschema, ''))

  ## Build out the table models.
  ##
  tables.each do |table|
    table[:model] = Class.new(base_class_for_new_models) do
      ## We can't assume table properties confom to any standard.
      ##
      self.table_name = table[:name]
      self.primary_key = table[:primary_key]

      ## Don't allow #find for tables with a composite primary key.
      ##
      def find(*args)
        raise Automodel::CannotFindOnCompoundPrimaryKey if table[:composite_primary_key]
        super
      end

      ## Create railsy column name aliases where necessary/possible.
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

  connection_handler
end

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

def railsy_column_name(column)
  case column.type
  when :boolean
    column.name.underscore.sub(%r{^is_}, '')
  else
    column.name.underscore
  end
end

# Automodel::SchemaInspector.register_adapter(
#   adapter: 'sqlserver',
#   tables: ->(connection) { connection.tables },
#   columns: ->(connection, table_name) { connection.columns(table_name) },
#   primary_key: ->(connection, table_name) { connection.primary_key(table_name) },
#   foreign_keys: ->(connection, table_name) { connection.foreign_keys(table_name) }
# )
