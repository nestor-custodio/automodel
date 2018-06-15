# Automodel  [![Gem Version](https://badge.fury.io/rb/automodel.svg)](https://badge.fury.io/rb/automodel)

Connecting your Rails application to a database created outside of the Rails environment usually means either spending hours writing up class files for every table, or giving up on using the ActiveRecord query DSL and resigning yourself to building SQL strings and making `execute`/`exec_query` calls.

Are those SQL strings you're building even injection-safe? Hmm... 😟

*With a single command*, **Automodel** lets you connect to any database and access all of its tables via the ActiveRecord DSL you've grown to love!

It does this by analyzing the table structures and:
- automatically defining all of the corresponding model classes
- declaring column aliases so you can use Railsy names an idioms
- constructing model relations based on foreign key definitions


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'automodel'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install automodel


## Using Automodel

The following examples all assume a Postgres database with the following tables:
```sql
-- Create Table: Authors
CREATE TABLE public."Authors" (
  "Author ID" serial  NOT NULL           ,
  "Name"      varchar NOT NULL DEFAULT '',
  "Birthday"  date        NULL           ,
  "Address"   varchar NOT NULL DEFAULT '',

  CONSTRAINT authors__pk PRIMARY KEY ("Author ID")
) WITH ( OIDS=FALSE );


-- Create Table: Publishers
CREATE TABLE public."Publishers" (
  "Publisher ID" serial  NOT NULL           ,
  "Name"         varchar NOT NULL DEFAULT '',
  "Address"      varchar NOT NULL DEFAULT '',
  "Website"      varchar NOT NULL DEFAULT '',

  CONSTRAINT publishers__pk PRIMARY KEY ("Publisher ID")
) WITH ( OIDS=FALSE );


-- Create Table: Books
CREATE TABLE public."Books" (
  "Book ID"         serial  NOT NULL              ,
  "Title"           varchar NOT NULL DEFAULT ''   ,
  "Edition"         int     NOT NULL DEFAULT 1    ,
  "ISBN Number"     varchar NOT NULL DEFAULT ''   ,
  "Published On"    date    NOT NULL              ,
  "Is Out Of Print" bool    NOT NULL DEFAULT FALSE,
  "Author ID"       bigint  NOT NULL              ,
  "Publisher ID"    bigint  NOT NULL              ,

  CONSTRAINT books__pk PRIMARY KEY ("Book ID"),

  CONSTRAINT books_authors_fk FOREIGN KEY ("Author ID")
                              REFERENCES public."Authors"("Author ID"),

  CONSTRAINT books_publishers_fk FOREIGN KEY ("Publisher ID")
                                 REFERENCES public."Publishers"("Publisher ID")
) WITH ( OIDS=FALSE );
```

---

#### Connecting To The External Database

You can provide the connection spec inline ...

```ruby
automodel adapter:  'postgresql' ,
          encoding: 'unicode'    ,
          host:     hostname     ,
          port:     port_number  ,
          username: username     ,
          password: password     ,
          database: database_name
```

... or you can use a connection spec defined in "config/database.yml" ...

```yml
## In "database.yml" ...

## ... (your application's own db connection stuff) ...


external_db:
  adapter:  postgresql
  pool:     <%= ENV.fetch('RAILS_MAX_THREADS') { 5 } %>
  timeouts: 5000
  encoding: unicode
  host:     name_or_ip
  port:     port_number
  username: username
  password: password
  database: sample_db
```

```ruby
## In "config/puma.rb" or "config/unicorn.rb" ...

automodel :external_db
```

---

#### Using The Automodel'ed Objects

Connecting via either method above will allow you to issue all of the following expressions, just as
if these were your own models:

```ruby
## ISBNs for all non-first-edition books.
isbn_list = Book.where.not(edition: 1).pluck(:isbn_number)

## Take any book and look up some values.
book = Book.take
book.title
book.out_of_print?
book.publisher.name


## Note that some ActiveRecord constructs surface real table names,
## which can look awkward in code when working with tables with non-Railsy names:
## (the uppercase "P" in "Publishers" below makes it look like a class reference)
Book.joins(:Publishers).where(Publishers: { name: test_value }).all
```

---

#### Automodel With Namespacing

If you're worried about model name collisions (or just want to keep the global namespace tidy), Automodel can define all of the new model classes under a module.

```ruby
automodel adapter:   'postgresql' ,
          encoding:  'unicode'    ,
          host:      hostname     ,
          port:      port_number  ,
          username:  username     ,
          password:  password     ,
          database:  database_name,
          namespace: 'ExternalDB'

## Now you can do everything you'd expect, but the models are namespaced under ExternalDB.
ExternalDB::Book.find(5)            ## => Book #5
ExternalDB::Book.take.author.class  ## => ExternalDB::Author

```

---

[Consult the repo docs for the full Automodel documentation.](http://nestor-custodio.github.io/automodel/Automodel.html)


## FAQs

- ##### Do I have to add anything to my Gemfile besides `'automodel'`?
  Only if you want to use connection adapters that are not yet part of your gemset. (e.g. Don't expect to be able to connect to a MySQL database without having added `'mysql2'` to your Gemfile.

- ##### But what about my application's own models?
  You can use Automodel **and** continue to use your application's own models without changing a single line of code.

- ##### Can I Automodel more than one database?
  Yes! You can Automodel as many databases with as many different adapters as you like. Automodel takes care of connecting to the various databases and managing their connection pools for you.

- ##### What about model name collisions?
  If an `automodel` call will result in a class name collision, an Automodel::NameCollisionError is raised *before* any classes are clobbered.

- ##### What if I want custom methods for certain models?
  You can either monkey-patch your methods onto the applicable Automodel-generated classes once they've been defined, or you can monkey-patch the method onto the connection handler class returned by the `automodel` call itself, which will make it available for all models generated *by that call*.

- ##### What if I'm using ActiveRecord but not Rails?
  That's no problem at all! The **automodel** gem's *only* dependency is ActiveRecord  -- not Rails. Adding `'automodel'` to your Gemfile (along with any relevant connection adapters, of course) is all you need to make use of the tool in your vanilla-Ruby project. Just be mindful that -- since "config/database.yml" isn't available (as you're not using Rails) -- you'll always need to pass in a full connection spec to your `automodel` calls (as in the very first example, under *"Connecting To The External Database"* above).


## Feature Roadmap / Future Development

Additional features/options coming in the future:

- **Naming**: Better generation of Railsy names for `:date`/`:datetime` column types.
- **Reads**: Support for `#find` on tables with composite primary keys.
- **Writes**: Better handling of missing `created_at`/`updated_at` columns on record creation/updates.
- **Traversal**: Support for `has_many` relations (only `belongs_to` is currently supported).
- **Traversal**: Support for self-referential foreign keys.
- **Traversal**: Support for multiple relations to the same target model.


## Contribution / Development

Bug reports and pull requests are welcome on GitHub at https://github.com/nestor-custodio/automodel.

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Linting is courtesy of [Rubocop](https://github.com/bbatsov/rubocop) and documentation is built using [Yard](https://yardoc.org/). Neither is included in the Gemspec; you'll need to install these locally (`gem install rubocop yard`) to take advantage.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
