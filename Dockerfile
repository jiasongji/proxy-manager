FROM ghcr.io/sagernet/sing-box:latest

LABEL org.opencontainers.image.title="proxy-manager-sing-box"
LABEL org.opencontainers.image.description="sing-box runtime image for Proxy Manager deployments"
LABEL org.opencontainers.image.source="https://github.com/jiasongji/proxy-manager"
LABEL org.opencontainers.image.licenses="MIT"

ENTRYPOINT ["sing-box"]
