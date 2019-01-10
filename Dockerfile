ARG TIMESCALE_VERSION=0.11.0-pg10
ARG POINTCLOUD_VERSION=1.2.0
ARG POINTCLOUD_VERSION_GIT=v${POINTCLOUD_VERSION}

FROM timescale/timescaledb-postgis:$TIMESCALE_VERSION  as builder

# necessary for it to build the FDW, for some reason
ENV USE_PGXS = 1

RUN apk add --update  build-base git cmake make libuv libuv-dev
RUN apk add --no-cache --virtual .fetch-deps \
    ca-certificates \
    openssl \
    tar \
    openssl-dev \
    autoconf \
    automake \
    zlib-dev \
    libxml2 \
    libxml2-dev \
  && wget -O postgresql.tar.bz2 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" \
  && mkdir -p /usr/src/postgresql \
  && tar \
    --extract \
    --file postgresql.tar.bz2 \
    --directory /usr/src/postgresql \
    --strip-components 1 \
  && rm postgresql.tar.bz2

WORKDIR /usr/src/postgresql/contrib

RUN git clone https://github.com/verma/laz-perf.git && \
    cd laz-perf && \
    cmake . && \
    make && \
    make install


RUN git clone https://github.com/pgpointcloud/pointcloud.git \
    && cd pointcloud \
    && git checkout $POINTCLOUD_VERSION_GIT \
    && ./autogen.sh \
    && ./configure --help \
    # NESTED_QSORT is required because Alpine/musl doesn't have qsort_r
    # -Wno-error=trampolines because it'll fail otherwise
    && ./configure CFLAGS="-Wall -Werror -O2 -g -DNESTED_QSORT=1 -Wno-error=trampolines" --with-lazperf=/usr/local \
    && make \
    && make install

# now for the real image

FROM timescale/timescaledb-postgis:$TIMESCALE_VERSION

# copy pointcloud stuff
COPY --from=builder /usr/local/lib/postgresql/pointcloud-*.so /usr/local/lib/postgresql/

# this dir has the pointcloud extension
COPY --from=builder /usr/local/share/postgresql/extension/ /usr/local/share/postgresql/extension

# the update_hba_config.sh script uses jq, which isn't installed by  default on alpine
RUN apk --no-cache add \
  # required for runtime hba_config modification
  jq \
  # required for cassadra c driver
  libuv \
  libxml2 \
  zlib

EXPOSE 5432
VOLUME  ["/var/log/postgresql", "/var/lib/postgresql"]

