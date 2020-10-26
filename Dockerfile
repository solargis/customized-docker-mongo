ARG MONGO_TAG=4.2
FROM mongo:$MONGO_TAG as daemonizer
RUN apt-get update && apt-get install -y --no-install-recommends curl build-essential git
RUN curl -sL https://github.com/bmc/daemonize/archive/release-1.7.8.tar.gz | tar xzf - \
  && cd daemonize-* && sh configure && make && mkdir /out && cp ./daemonize /out
RUN curl -sL https://golang.org/dl/go1.15.3.linux-amd64.tar.gz | tar xzf - -C /usr/local
ENV PATH="$PATH:/usr/local/go/bin"
#RUN go get go.mongodb.org/mongo-driver/mongo
COPY src /initializer
WORKDIR /initializer
RUN go build && chmod +x /initializer/initializer && cp /initializer/initializer /out

ARG MONGO_TAG=4.2
FROM mongo:$MONGO_TAG
COPY --from=daemonizer /out /usr/local/bin
RUN mkhomedir_helper mongodb \
  && awk '/MongoDB init process complete; ready for start up\./ {x=1} {print} \
    x==1 && $1=="fi" && NF==1 { x=0; \
      print "\n\tfor f in /docker-hooks.d/prestart-*.sh; do"; \
      print "\t\tif [ -f \"$f\" ]; then echo \"$0: running $f\"; . \"$f\"; fi"; \
      print "\tdone"; \
    }' /usr/local/bin/docker-entrypoint.sh \
  | awk '$1=="originalArgOne=\"$1\"" && NF==1 { \
      print "if [ \"$(id -u)\" -eq 0 ]; then"; \
      print "\tfor f in /docker-hooks.d/postboot-*.sh; do"; \
      print "\t\tif [ -f \"$f\" ]; then echo \"$0: running $f\"; . \"$f\"; fi"; \
      print "\tdone"; \
      print "fi\n\n" $1; \
      next;\
    } {print}' > /usr/local/bin/docker-entrypoint.sh~ \
  && cat /usr/local/bin/docker-entrypoint.sh~ > /usr/local/bin/docker-entrypoint.sh \
  && rm /usr/local/bin/docker-entrypoint.sh~
COPY ./docker-hooks.d/ /docker-hooks.d/
COPY ./lib/ /usr/local/lib/
