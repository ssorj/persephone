# Troubleshooting

## Some install directories are not writable

- Change directory permissions

- Install as a different user who does have write permission

## Some required programs are not available

- Use your OS's package manager to look up and install things

## Some required ports are in use by something else

- Check if you have Artemis already running

- Use `lsof` or `netstat` to identify the processes using the ports
  and terminate them

## Some required network resources are not available

- Check your network

- Use traceroute to find out where connectivity falters

## Java is available, but it is not working

- This seems to be a problem on Mac OS - Try using Temurin via Brew

## The checksum does not match the downloaded release archive

- Try blowing away the cached download
