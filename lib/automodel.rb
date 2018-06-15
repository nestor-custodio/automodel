require 'active_record'
require 'active_support/all'
require 'securerandom'

require 'automodel/automodel'
require 'automodel/connectors'
require 'automodel/helpers'
require 'automodel/version'

## The main (really *only*) entrypoint for the Automodel gem. This is the method the end-user calls
## to trigger a database scrape and model generation.
##
##
## @param spec [Symbol, String, Hash]
##   The Symbol/String/Hash to pass through to the ActiveRecord connection resolver, as detailed in
##   [ActiveRecord::ConnectionHandling#establish_connection](http://bit.ly/2JQdA8c). Whether the
##   given "spec" value is a Hash or is a Symbol/String to run through the ActiveRecord resolver,
##   the resulting Hash may include the following options (in addition to the actual connection
##   parameters).
##
## @option spec [String] :subschema
##   The name of an additional namespace with which tables in the target database are prefixed.
##   Intended for use with SQL Server, where a table's fully-qualified name may have an additional
##   level of namespacing between the database name and the base table name (e.g.
##   `database.dbo.table`, in which case the subschema would be `"dbo"`).
##
## @option spec [String] :namespace
##   A String representing the desired namespace for the generated model classes (e.g. `"NewDB"` or
##   `"WeirdDB::Models"`). If not given, the generated models will fall under `Kernel` so they are
##   always available without namespacing, like standard user-defined model classes.
##
##
## @raise [Automodel::ModelNameCollisionError]
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
  connection_handler_name = "CH_#{SecureRandom.uuid.delete('-')}"
  base_class_for_new_models = connection_handler = Class.new(ActiveRecord::Base)
  Automodel::Helpers.register_class(connection_handler, as: connection_handler_name,
                                                        within: :'Automodel::Connectors')

  ## Establish a connection with the given params.
  ##
  connection_handler.establish_connection(connection_spec)

  ## Map out the table structures.
  ##
  tables = Automodel::Helpers.map_tables(connection_handler, subschema: connection_spec[:subschema])

  ## Safeguard against class name collisions.
  ##
  defined_names = Array((connection_spec[:namespace] || :Kernel).to_s.safe_constantize&.constants)
  potential_names = tables.map { |table| table[:model_name].to_sym }
  name_collisions = defined_names & potential_names
  if name_collisions.present?
    connection_handler.connection_pool.disconnect!
    Automodel::Connectors.send(:remove_const, connection_handler_name)
    raise Automodel::NameCollisionError, name_collisions
  end

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
        raise Automodel::FindOnCompoundPrimaryKeyError if table[:composite_primary_key]
        super
      end

      ## Create railsy column name aliases whenever possible.
      ##
      table[:columns].each do |column|
        railsy_name = Automodel::Helpers.railsy_column_name(column)
        unless table[:column_aliases].key? railsy_name
          table[:column_aliases][railsy_name] = column
          alias_attribute(railsy_name, column.name)
        end
      end
    end

    ## Register the model class.
    ##
    Automodel::Helpers.register_class(table[:model], as: table[:model_name],
                                                     within: connection_spec[:namespace])
  end

  ## With all models registered, we can safely declare relationships.
  ##
  tables.map { |table| table[:foreign_keys] }.flatten.each do |fk|
    from_table = tables.find { |table| table[:base_name] == fk.from_table.delete('"') }
    next unless from_table.present?

    to_table = tables.find { |table| table[:base_name] == fk.to_table.delete('"') }
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
