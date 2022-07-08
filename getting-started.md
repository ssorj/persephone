# Getting started with ActiveMQ Artemis

## Step 1: Install the broker

~~~ shell
curl -f https://raw.githubusercontent.com/ssorj/persephone/main/install.sh | sh
~~~

## Step 2: Install Qtools XXX

## Step 3: Start the broker

~~~ shell
artemis run
~~~

## Step 4: Create a queue

~~~ shell
artemis queue create --name greetings --address greetings --auto-create-address --anycast --silent
~~~

## Step 5: Send a message

~~~ shell
qsend amqp://localhost/greetings hello
~~~

## Step 6: Receive a message

~~~ shell
qreceive amqp://localhost/greetings --count 1
~~~

## Stopping the broker

~~~ shell
artemis stop
~~~

## Logging

## TLS

## User and password

## Creating queues and topics

## Accessing the console

XXX Basic login procedure

### The default console user and password

By default, the install script creates a user named "example" with a
generated password.  The password is printed in the install script
summary.

~~~
== Summary ==

   SUCCESS

   ActiveMQ Artemis is now installed.

       Version:           2.23.1
       Config files:      /home/jross/.config/artemis
       Log files:         /home/jross/.local/state/artemis/log
       Console user:      example
       Console password:  7yjcx0l0w7k48v1a
~~~

### Changing the example user password

XXX

## Writing a client program

XXX Choose your language and write a messaging-based application
