FROM cgr.dev/chainguard/docker-dind:latest-dev@sha256:bdceba6dd66e1e1166d5ae8e381b61579f0384fe84c223cd29dc0a7571ebe124

RUN apk add trufflehog jq curl cosign grype supervisor
COPY *.sh .

ENTRYPOINT ["/entrypoint.sh"]
