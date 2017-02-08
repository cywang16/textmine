# 
FROM perl
RUN mkdir -p /usr/src/myapp
ADD daemon.pl /usr/src/myapp/
ADD entrypoint.sh /usr/src/myapp/
RUN chmod +x /usr/src/myapp/entrypoint.sh  /usr/src/myapp/daemon.pl
WORKDIR /usr/src/myapp
# CMD ["./daemon.pl"]
CMD ["./entrypoint.sh"]
