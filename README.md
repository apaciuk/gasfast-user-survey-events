# gasfast-user-survey-events

Rails app to capture survey selection event data from users in surveys.

# What is Event Sourcing?

Event Sourcing is a system design pattern that emphasizes recording changes to data via immutable events.

In other words: *every time your data changes*, you save an event to your database with the details. 

**Those events never change or go away.** That way, you have a permanent, unchanging history of how your data reached its current state!

# What this app covers
We will primarily be working off of [Kickstarter's event sourcing example.](https://kickstarter.engineering/event-sourcing-made-simple-4a2625113224)

Once Base User Event pattern is set up, it can be expanded to include other events related to the user, to start we just set up the user created and destroyed events which are stored in the user_events table

To create our Base Event pattern, we’ll take the following steps:
-   Get our Rails app up and running
	-  	`User` model and controller
	-   PostgreSQL for our database
-   Set up our environment to test our Events
	-   Postman or Swagger for REST client
-   Add our Events pattern
	-   What is an Event, and what Event data will we store in the database?
	-   The BaseEvent that other Event classes will inherit from
	-   `Events::User::Created`
	-   `Events::User::Destroyed`
# What is an Event?
In our event sourcing system, each Event will be **a Rails model that stores information about changes to our data**. 

Our goal is to build two events:
-   `Events::User::Created` — this will record:
	-   `payload`: a hash containing the `name`, `email`, and `password` params to create the User
	-   `user_id`: the created User’s `id`, used as a `belongs_to` relationship
	-   `event_type`: a String to show that this `user_event` is the `”Created”` type
	-   timestamps
-   `Events::User::Destroyed` — this will record:
	-   `payload`: a hash containing the `id` for the User to be flagged as deleted
	-   `user_id`: the target User’s `id`, used as a `belongs_to` relationship
	-   `event_type`: a String to show that this `user_event` is the `”Destroyed”` type
	-   timestamps

When our Rails app creates or destroys a User, this will also trigger creating a new Event.

These events will be saved to our database, and will be **immutable** to serve as a permanent log of changes.

Since we might end up having _a lot_ of User-related events, we’re also including the `event_type` field on our User events so we can store them all in one `user_events` table—and easily add add more later!

## `apply(aggregate)` and `apply_and_persist`
Each event will have to define its own `apply` method. This method will accept an `aggregate`—another model, in our case a User—and update its attributes.
_(The term `aggregate` comes from the Kickstarter event sourcing system, and [you can read more about it here](https://kickstarter.engineering/event-sourcing-made-simple-4a2625113224). Basically, `aggregates` are models that receive changes via `events`.)_

On BaseEvent, we’ll simply raise a `NotImplementedError`. This will enforce us having to define it explicitly on each event, thus overriding the error via inheritance.

The BaseEvent will also have a `before_create` hook that calls `apply_and_persist`. This will call `apply`, then `save!` the update to the database. 
_(It will also set the event’s `aggregate_id`, specifically for Created events where the `id` doesn’t exist until after `save!` is called.)_

## `aggregate` setters, getters, and get-its-namers
To round out our events’ functionality, we’ll want some setters and getters—as well as methods to easily return its type or class name:
-   `aggregate=(model)` and `aggregate` will set and get the User our event targets
-   `aggregate_id=(id)` and `aggregate_id` will map to the `user_id` field on our `user_events` table
-   `self.aggregate_name` gives the Event class awareness of its `belongs_to` relationship’s target class (`#=> User`)
-   `delegate :aggregate_name, to: :class` will return a Symbol of the aggregate’s class name (`#=> :user`)
-   `def event_klass` will convert our Event class’s `::BaseEvent` namespace into its appropriate event type (`#=> Events::User::Created`)

# The `user_events` table, and the `Events::User::BaseEvent`
We previously mentioned that we will be storing multiple types of User-related events in a single `user_events` table. 

To accomplish this and allow us to easily add more events later, we will create an `Events::User::BaseEvent` which will tell all events in the `Events::User::` namespace to save to the `user_events` table. We will also define a `belongs_to` relationship with a User here.

## `user_events` table
Let’s go ahead and create our `user_events` table in our database.

[Kickstarter’s event sourcing example](https://kickstarter.engineering/event-sourcing-made-simple-4a2625113224) describes that each `aggregate` (User) has an event table (`user_events`). These event tables will have a similar schema—we will tweak them slightly to match our verbiage:
> Each Aggregate (ex: survey) has an Event table associated to it (ex: survey_events).
> …
> All events related to an aggregate are stored in the same table. All events tables have a similar schema:
> `id, aggregate_id, type, data (json), metadata (json), created_at`

A few things we’ll tweak for our code:
-   `aggregate_id` will be replaced by `user_id`
-   `type` will be replaced by `event_type` (just to be more explicit)
-   `data` will be replaced by `payload`, and will still be type JSON
-   `metadata` will not be included at this time, since our events are relatively simple
-   `created_at` will not be included, since we will simply rely on ActiveRecord’s default timestamps

We will create our `user_events` table with a Rails migration:
```ruby
rails g migration CreateUserEvents
```
We want to add four fields:
-   a `belongs_to` relationship to a `:user`
-   an `event_type` String
-   a `payload` JSON
-   timestamps

```ruby
# db/migrate/20200502192018_create_user_events.rb
class CreateUserEvents < ActiveRecord::Migration[6.0]
  def change
    create_table :user_events do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.string :event_type
      t.json :payload

      t.timestamps
    end
  end
end
```
## `Events::User::BaseEvent`
Inside our `app/models/events` directory, create a new `user` directory.

Inside that directory, create a new file `base_event.rb`. This gives us the namespacing to create this class:
```ruby
# app/models/events/user/base_event.rb

class Events::User::BaseEvent < Events::BaseEvent
  self.table_name = "user_events"
end
```
With `self.table_name = “user_events”`, any new Event class we create that inherits from `Events::User::BaseEvent` will automatically be saved and retrieved from the `user_events` table!


## `belongs_to :user` and `has_many :events`
Since all our User-related events target a User, it makes sense to create a `has_many / belongs_to` relationship between Users and Events in the `Events::User::` namespace.

Since we’re deep in a namespace that uses the name `User`, to tell Rails to look for the regular top-level `User` model, we need to add `::` before our classnames. This tells our `has_many` and `belongs_to` relationships to look outside the current namespace.

Update the `Events::User::BaseEvent` and `User` classes with the relationships:
```ruby
# app/models/events/user/base_event.rb
class Events::User::BaseEvent < Events::BaseEvent
  self.table_name = "user_events"

  belongs_to :user, class_name: "::User"
end
# app/models/user.rb

class User < ApplicationRecord
  has_many :events, class_name: "Events::User::BaseEvent" 
end
```
Now, when we load a User into a `user` variable, we can call `user.events` to load all related events from the `user_events` table.

**We’re now ready to create some real, _usable_ Events!**
# Creating a new User with `Events::User::Created`
With our BaseEvent pattern in place, we can now build our first event!

`Events::User::Created` will record the params used to create a User, as well as the new User’s id, and the event’s timestamp.

## Build the `Events::User::Created` class
In `app/models/events/user`, make a new `created.rb` file. Our class will inherit from `Events::User::BaseEvent` in the same directory:
```ruby
# app/models/events/user/created.rb

class Events::User::Created < Events::User::BaseEvent
end
```

As we defined in the top-level `Events::BaseEvent`, we must define an `apply` method that will take a User instance as its `aggregate` argument:
```ruby
# app/models/events/user/created.rb

class Events::User::Created < Events::User::BaseEvent
  def apply(user)
  end
end
```

Since we know creating a User requires params with a `name`, `email`, and `password`, we can also add them as a list of symbols to `payload_attributes` to create our getters and setters:
```ruby
# app/models/events/user/created.rb

class Events::User::Created < Events::User::BaseEvent
  payload_attributes :name, :email, :password

  def apply(user)
  end
end
```

## Add logic to the `apply` method
The logic in the event’s `apply` method is where the event’s power lies. It:
-   takes in a User instance
-   applies the changes to the User instance, supplied by `payload_attributes`
-   returns the mutated User instance => **this is where the top-level BaseEvent receives back the User instance, and calls `save!` to persist the changes in the database!**

Thanks to the list of attributes passed to `payload_attributes`, we can simply call the attributes inside our `apply` method to update the User instance:
```ruby
# app/models/events/user/created.rb

payload_attributes :name, :email, :password

def apply(user)
  user.name = name
  user.email = email
  user.password_digest = password

  user
end
```
## Update our controller to create an Event and use strong params
Back in our `users_controller`, we need to update two things:
-   the `create` action needs to call `Events::User::Created.create(payload: user_params)`
-   add strong params to protect the `user_params` we will pass to `.create(payload: user_params)`

For the strong params, we will require the `user_params` to have `name`, `email`, and `password` nested inside a `user` key:
```ruby
# app/controllers/users_controller.rb

private def user_params
  params.require(:user).permit(:name, :email, :password)
end
```

Now, we can safely pass `user_params` to `Events::User::Created.create(payload: user_params)` in the `create` action:
```ruby
# app/controllers/users_controller.rb

def create
  Events::User::Created.create(payload: user_params)
end

private def user_params
  params.require(:user).permit(:name, :email, :password)
end
```

## Let’s test our event with Insomnia and Postico!
If we send the correct params via a POST request to `localhost:3000/users/create`, we expect several behaviors:
-   a new record in the `user_events` table, with:
	-   `event_type “Created”`
	-   `payload` with the `user_params`
		-   note that the `password` will be stored as plaintext => **this is UNSAFE BEHAVIOR, and is because we have not implemented bcrypt encryption yet!**
	-   `user_id` with the newly-created User’s `id`
-   a new record in the `user` table, with:
	-   correct `name`
	-   correct `email`
	-   `password_digest` that is the plaintext `password` => **this is UNSAFE BEHAVIOR, and is because we have not implemented bcrypt encryption yet!**

# Destroying a User with `Events::User::Destroyed`
Now that we have our pattern in place, it’s very straightforward to create a new Event and record it to our `user_events` table!

Since we **never want to destroy our data**, we implemented a boolean `deleted` field on the User model. When a new User is created, it defaults to `false`.

Let’s create a new event, `Events::User::Destroyed`, that will set the `deleted` field to `true`!

## Create an `app/models/events/user/destroy.rb` file
In the same directory as our `Events::User::Created` class, create an equivalent `Events::User::Destroyed` class:
```ruby
# app/models/events/user/destroy.rb

class Events::User::Destroyed < Events::User::BaseEvent
  def apply(user)
    user
  end
end
```
Above, we start with an `apply` method that simply returns the passed-in User instance.

To delete a User, we’ll simply require an `id`. Let’s add the `payload_attributes` for it:
```ruby
# app/models/events/user/destroy.rb

class Events::User::Destroyed < Events::User::BaseEvent
  payload_attributes :id
end
```

And we’ll make our `apply` method update the passed-in User’s `deleted` field to `true`:
```ruby
# app/models/events/user/destroy.rb

class Events::User::Destroyed < Events::User::BaseEvent
  payload_attributes :id
  
  def apply(user)
    user.deleted = true
    
    user
  end
end
```

That’s it—our new Event is done!


## Update the `destroy` action in `users_controller`
In our `users_controller`, we’ll make our `destroy` action simply create our new `Events::User::Destroyed` event.

Thanks to the `find_or_build_aggregate` and `aggregate_id` methods defined in our top-level BaseEvent, this `”Destroyed”` event will look up a User automatically if a `user_id` argument is supplied.

First, let’s add `id` to the list of strong params in `user_params`:
```ruby
# app/controllers/users_controller.rb

private def user_params
  params.require(:user).permit(:name, :email, :password, :id)
end
```

Now, our controller’s `destroy` action can accept a `user_params` that has the necessary `id`. We’ll also use `user_params[:id]` so the event can look up our target User’s record:
```ruby
# app/controllers/users_controller.rb

def destroy
  Events::User::Destroyed.create(user_id: user_params[:id], payload: user_params)
end
```

We’re ready to go ahead and test with Postman!

## Test a DELETE request in Postman
Let’s fire up `rails s`. 

Create a new request called `Destroy User` in Postman and make it a DELETE:

Set its target URL to `localhost:3000/users/destroy`:

Set the Body type to JSON, and add a hash with a `”user”` key pointing to a hash containing the `”id”`:

Hit Send, and check the database to see if the Event was created:

And finally, let’s check the database to see if our User has `deleted` set to `true`:

We get to keep our User record, but also have it be `deleted`

**That’s all it takes to add a new event to our event sourcing system!**

# Conclusion

-   Create a new Rails app, with a User model and controller, and PostgreSQL for the database
-   Create an `Events::BaseEvent` class in `app/models/events` to handle Event logic:
	-   Looking up or creating aggregates (Users)
	-   Creating getters and setters for `payload_attributes`
	-   Inferring its own `event_type`
	-   Hooks for automatically applying changes and saving to the database
-   Create a `user_events` table migration
-   Create an `Events::User::BaseEvent` to save all Events in its `Events::User::` namespace to the `user_events` table
-   Create an `Events::User::Created` event that will apply `user_params` to a new User instance
-   Create an `Events::User::Destroyed` event that will look up at User by `id` and set its `deleted` field to `true`

This minimal system allows us to do the following:
-   Have a record of events that create and destroy Users
-   Keep all User data permanently, and still have the ability to scope the `deleted` ones as needed
-   A pattern that allows us to easily add new Events that will be saved to the same `user_events` table


