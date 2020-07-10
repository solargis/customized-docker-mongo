ARG MONGO_TAG=4.2
FROM mongo:$MONGO_TAG
RUN mkhomedir_helper mongodb \
  && awk '/MongoDB init process complete; ready for start up\./ {x=1} {print} \
    x==1 && $1=="fi" && NF==1 { x=0;\
      print "\n\tfor f in /docker-entrypoint-startdb.d/*; do";\
      print "\t\tif [ -f \"$f\" ]; then echo \"$0: running $f\"; . \"$f\"; fi";\
      print "\tdone";\
    }' /usr/local/bin/docker-entrypoint.sh > /usr/local/bin/docker-entrypoint.sh~ \
  && mv /usr/local/bin/docker-entrypoint.sh~ /usr/local/bin/docker-entrypoint.sh && chmod ug+w,+x /usr/local/bin/docker-entrypoint.sh

COPY ./docker-entrypoint-startdb.d/ /docker-entrypoint-startdb.d/
