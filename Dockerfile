FROM centos:7.5.1804
LABEL maintainer="wuxingzhong <wuxingzhong@sunniwell.net>"

RUN set -x \
	&& BUILD_DEPS=" \
		wget \
        curl \
        git \
        hg \
        pkg-config \
        patch \
        gcc \
        gcc-c++ \
        make \
        cmake \
        autotools \
        autoconf \
        automake \
        "\
    && yum install -y ${BUILD_DEPS}

ADD  build.sh /opt/
WORKDIR /opt/
RUN chmod +x ./build.sh \
    && ./build.sh

CMD [ "/bin/bash" ]
