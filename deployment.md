# Deploying ActiveMQ Artemis

## Removing the example user and adding another user

XXX

## Configuring TLS

## Opening up network access

## Disabling automatic address and queue creation

## Creating queues and topics

## Installing Artemis as a system service

## Accessing the console

## Persistence!

## HA!

## Logging

## More resources

### Changing passwords

    # Prereq: The broker must be running
    artemis user reset --user-command-user example --user-command-password example

### Adding users

    # Prereq: The broker must be running
    artemis user add --user-command-user alice --user-command-password secret --role amq
    # XXX: How would the user know what role to use, and know about what "amq" is for?

### Removing users

    # Prereq: The broker must be running
    artemis user rm --user-command-user alice
