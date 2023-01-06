ARG DEBIAN_BASE_IMAGE_TAG=bullseye-20200224-slim
FROM debian:$DEBIAN_BASE_IMAGE_TAG

RUN apt-get -o Acquire::Check-Valid-Until=false update

RUN apt-get install -y --allow-downgrades --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      binutils \
      wget && \
    apt autoremove -y

ARG HELM_VERSION=3.10.3

RUN curl --silent \
    https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    | tar xvzf - \
    && mv linux-amd64/helm /usr/local/bin/helm

RUN apt-get -o Acquire::Check-Valid-Until=false update && apt install shellcheck

RUN wget https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz && \
    tar xf kubeconform-linux-amd64.tar.gz && \
    cp kubeconform /usr/local/bin

COPY helm /app/helm
COPY resources /app/resources

RUN mkdir /repo

WORKDIR /app
# The tests create some temp files there
RUN chmod go+w /app
