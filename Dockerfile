FROM openjdk:8u121-jre-alpine

ADD target/universal/cade /opt/cade
ADD cade.sh /opt/cade
ADD version.txt /version.txt
ADD deps/terraform /opt/terraform
RUN apk update && \
    apk add bash && \
    # -x removes execute permissions for all, +X will add execute permissions for all, but only for directories. \
    chmod -x+X -R /opt/cade && \
    chmod a+x /opt/cade/bin/cade && \
    rm -Rf /var/cache/apk/*

CMD /opt/cade/bin/cade
