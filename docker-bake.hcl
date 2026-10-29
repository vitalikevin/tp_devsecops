variable "REGISTRY" {
  default = "ghcr.io/vitalikevin/tp_devsecops"
}

variable "VERSION" {
  default = "dev"
}

group "default" {
  targets = ["api"]
}

# Tag par défaut en local, remplacé en CI par les tags SemVer de docker/metadata-action
target "docker-metadata-action" {
  tags = ["${REGISTRY}/api:${VERSION}"]
}

target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  secret     = ["id=pip_config,src=secrets/pip.conf"]
  cache-from = ["type=gha,scope=api"]
  cache-to   = ["type=gha,scope=api,mode=max"]
}

target "api" {
  inherits  = ["_common", "docker-metadata-action"]
  platforms = ["linux/amd64", "linux/arm64"]
}

# Image amd64 chargée dans Docker pour Dive, Trivy et Compose

target "api-ci" {
  inherits  = ["_common"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/api:ci"]
  output    = ["type=docker"]
}
