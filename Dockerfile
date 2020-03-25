FROM arm64v8/debian:stretch-slim as Builder
RUN apt-get update && \
    apt-get install -y fakeroot ca-certificates txt2man equivs devscripts mercurial liblua5.2-dev libidn11-dev libssl-dev build-essential && \
    hg clone https://hg.prosody.im/0.11/ prosody-0.11 && \
    hg clone https://hg.prosody.im/debian/ prosody-0.11/debian && \
    cd prosody* && \
    dch -v 0.11~$(hg id -i)-1 "I build my own" && \
    mk-build-deps -ri && \
    debuild -us -uc -B

FROM arm64v8/debian:stretch-slim as Final
MAINTAINER Victor Kulichenko <onclev@gmail.com>
COPY --from=Builder /prosody_0.11~*-1_arm64.deb /packages/prosody_arm64.deb

#COPY prosody.list /etc/apt/sources.list.d/
COPY ./entrypoint.sh /usr/bin/entrypoint.sh
COPY ./update-modules.sh /usr/bin/update-modules
COPY ./check_prosody_update.sh /usr/bin/check_prosody_update
ARG PROSODY_VERSION
ENV PROSODY_VERSION=${PROSODY_VERSION} \
    PUID=${PUID:-1000} PGID=${PGID:-1000} \
    PROSODY_MODULES=/usr/lib/prosody/modules-community \
    CUSTOM_MODULES=/usr/lib/prosody/modules-custom

# create prosody user with uid and gid predefined
RUN groupadd -g $PGID -r prosody && useradd -b /var/lib -m -g $PGID -u $PUID -r -s /bin/bash prosody

# install prosody, mercurial, and recommended dependencies, prosody-modules locations, tweak and preserve config
RUN apt-get update && apt-get install -y gnupg2
RUN set -x \
 && apt-get update -qq \
 && apt install /packages/prosody_arm64.deb -y \
 && apt-get install -qy lua-sec lua-event lua-zlib lua-ldap lua-dbi-mysql lua-dbi-postgresql lua-dbi-sqlite3 lua-bitop \
 && apt-get purge apt-utils -qy \
 && apt-get clean && rm -Rf /var/lib/apt/lists \
 && sed -i -e '1s/^/daemonize = false;\n/' -e 's/daemonize = true/-- daemonize = true/g' /etc/prosody/prosody.cfg.lua \
 && perl -i -pe '$_ = qq[\n-- These paths are searched in the order specified, and before the default path\nplugin_paths = { \"$ENV{CUSTOM_MODULES}\", \"$ENV{PROSODY_MODULES}\" }\n\n$_] if $_ eq qq[modules_enabled = {\n]' \
         /etc/prosody/prosody.cfg.lua \
 && perl -i -pe 'BEGIN{undef $/;} s/^log = {.*?^}$/log = {\n    {levels = {min = "info"}, to = "console"};\n}/smg' /etc/prosody/prosody.cfg.lua \
 && mkdir -p /var/run/prosody && chown prosody:adm /var/run/prosody \
 && cp -Rv /etc/prosody /etc/prosody.default && chown prosody:prosody -Rv /etc/prosody /etc/prosody.default \
 && mkdir -p "$PROSODY_MODULES" && chown prosody:prosody -R "$PROSODY_MODULES" && mkdir -p "$CUSTOM_MODULES" && chown prosody:prosody -R "$CUSTOM_MODULES" \
 && chmod 755 /usr/bin/entrypoint.sh /usr/bin/update-modules /usr/bin/check_prosody_update

RUN rm /packages/prosody_arm64.deb && rmdir /packages

VOLUME ["/etc/prosody", "/var/lib/prosody", "/var/log/prosody", "$PROSODY_MODULES", "$CUSTOM_MODULES"]

USER prosody

ENTRYPOINT ["/usr/bin/entrypoint.sh"]

EXPOSE 80 443 5222 5269 5347 5280 5281
ENV __FLUSH_LOG yes
CMD ["prosody"]

