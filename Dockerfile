ARG MONGO_TAG=4.2
FROM mongo:$MONGO_TAG
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
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "mongo", "--quiet", "/docker-hooks.d/health-check.js" ]
