FROM docker.wdf.sap.corp:51022/com.sap.ai/gardenlinux-dev:318.8.0-sap4

ARG HELM_VERSION=3.5.2

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