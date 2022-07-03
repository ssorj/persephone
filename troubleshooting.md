# Troubleshooting

## Some required ports are in use by something else

- Check if you have Artemis already running.

- Use `lsof` or `netstat` to identify the processes using the ports
  and terminate them.
