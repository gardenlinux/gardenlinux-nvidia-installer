ARG DEBIAN_BASE_IMAGE_TAG=bullseye-20200224-slim
FROM debian:$DEBIAN_BASE_IMAGE_TAG

RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=true update

RUN apt-get install -y --allow-downgrades --no-install-recommends --allow-unauthenticated \
      build-essential \
      ca-certificates \
      curl \
      binutils \
      shellcheck \
      wget && \
    apt autoremove -y

ARG HELM_VERSION=3.12.0

RUN curl --silent \
    https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    | tar xvzf - \
    && mv linux-amd64/helm /usr/local/bin/helm

RUN wget https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz && \
    tar xf kubeconform-linux-amd64.tar.gz && \
    cp kubeconform /usr/local/bin

COPY helm /app/helm
COPY resources /app/resources

RUN mkdir /repo

WORKDIR /app
# The tests create some temp files there
RUN chmod go+w /app
