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
        nasm \
        gcc \
        g++ \
        make \
        cmake \
        autotools \
        autoreconf \
        "\
    && yum install -y ${BUILD_DEPS}

ADD  ffmpeg_build.sh /opt/
WORKDIR /opt/
RUN ./ffmpeg_build.sh

CMD [ "/bin/bash" ]