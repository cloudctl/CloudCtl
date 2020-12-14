FROM centos:latest as rpm
FROM registry:2 as registry
FROM docker.io/cloudctl/koffer-go:latest as koffer-go
FROM quay.io/openshift/origin-operator-registry:latest as olm
FROM registry.access.redhat.com/ubi8/ubi:latest as ubi8
FROM registry.access.redhat.com/ubi8/ubi:latest as ubi
FROM registry.access.redhat.com/ubi8/ubi:latest
#################################################################################
# OCP Version set in src/ocp
ARG varVerJq="${varVerJq}"
ARG varVerOpm="${varVerOpm}"
ARG varRunDate="${varRunDate}"
ARG varVerHelm="${varVerHelm}"
ARG varVerTpdk="${varVerOpenshift}"
ARG varVerGrpcurl="${varVerGrpcurl}"
ARG varVerOpenshift="${varVerOpenshift}"
ARG varVerTerraform="${varVerTerraform}"

# OC Download Urls
ARG urlOC="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-client-linux.tar.gz"
ARG urlOCINST="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-install-linux.tar.gz"

# Binary Artifact URLS
ARG varUrlGcloud="https://sdk.cloud.google.com"
ARG varUrlHelm="https://get.helm.sh/helm-v${varVerHelm}-linux-amd64.tar.gz"
ARG varUrlJq="https://github.com/stedolan/jq/releases/download/jq-${varVerJq}/jq-linux64"
ARG urlRelease="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/release.txt"
ARG varUrlOpm="https://github.com/operator-framework/operator-registry/releases/download/v${varVerOpm}/linux-amd64-opm"
ARG varUrlTerraform="https://releases.hashicorp.com/terraform/${varVerTerraform}/terraform_${varVerTerraform}_linux_amd64.zip"
ARG varUrlOsInst="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-install-linux.tar.gz"
ARG varUrlOpenshift="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-client-linux.tar.gz"
ARG varUrlGrpcurl="https://github.com/fullstorydev/grpcurl/releases/download/v${varVerGrpcurl}/grpcurl_${varVerGrpcurl}_linux_x86_64.tar.gz"

# Build Variables
ARG listManifest="/var/lib/koffer/release.list"

#################################################################################
# Package Lists
ARG varListRpms="\
             git \
             tree \
             tmux \
             pigz \
             rsync \
             unzip \
             skopeo \
             bsdtar \
             buildah \
             openssl \
             python3-pip \
             fuse-overlayfs \
             "
ARG varListPip="\
             ansible \
             passlib \
             "
ARG YUM_FLAGS="\
    -y \
    --nobest \
    --nogpgcheck \
    --allowerasing \
    --setopt=tsflags=nodocs \
    --disablerepo "ubi-8-appstream" \
    --disablerepo="ubi-8-codeready-builder" \
    --disablerepo="ubi-8-baseos" \
"
#################################################################################
# Load Artifacts

# From Repo
COPY bin/entrypoint /usr/bin/entrypoint
COPY bin/run_registry.sh /usr/bin/run_registry.sh
COPY conf/registry-config.yml /etc/docker/registry/config.yml
COPY conf/registries.conf /etc/containers/registries.conf

# From entrypoint cradle
COPY --from=koffer-go /root/koffer /usr/bin/koffer

# From origin-operator-registry:latest
COPY --from=olm /bin/registry-server  /usr/bin/registry-server
COPY --from=olm /bin/initializer  /usr/bin/initializer

# From Registry:2
COPY --from=registry /bin/registry  /bin/registry

# From CentOS
COPY --from=rpm /etc/pki/ /etc/pki
COPY --from=rpm /etc/yum.repos.d/ /etc/yum.repos.d

# From CentOS (aux testing)
COPY --from=rpm /etc/os-release /etc/os-release
COPY --from=rpm /etc/redhat-release /etc/redhat-release
COPY --from=rpm /etc/system-release /etc/system-release
#################################################################################
# Create Artifact Directories
RUN set -ex                                                                     \
     && mkdir -p /var/lib/koffer/                                               \
     && curl -sL ${urlRelease}                                                  \
      | awk -F'[ ]' '/Pull From:/{print $3}'                                    \
      | sed 's/quay.io\///g'                                                    \
      | tee -a ${listManifest}                                                  \
     && curl -sL ${urlRelease}                                                  \
      | grep -v 'Pull From'                                                     \
      | awk '/quay.io\/openshift-release/{print $2}'                            \
      | sed 's/quay.io\///g'                                                    \
      | tee -a ${listManifest}                                                  \
     && dnf update ${YUM_FLAGS}                                                 \
     && dnf -y module disable container-tools \
     && dnf -y install 'dnf-command(copr)' \
     && dnf -y copr enable rhcontainerbot/container-selinux \
     && curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo \
          https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo \
     && dnf update ${YUM_FLAGS}                                                 \
     && dnf install ${YUM_FLAGS} ${varListRpms}                                 \
     && pip3 install ${varListPip}                                              \
     && dnf install ${YUM_FLAGS} bsdtar tar                                     \
     && curl -L ${varUrlGrpcurl}                                                \
          | tar xzvf - --directory /tmp grpcurl                                 \
     && mv /tmp/grpcurl   /bin/grpcurl                                          \
     && curl -L ${varUrlHelm}                                                   \
          | tar xzvf - --directory /tmp linux-amd64/helm                        \
     && mv /tmp/linux-amd64/helm   /bin/                                        \
     && curl -L ${varUrlTerraform}                                              \
          | bsdtar -xvf- -C /bin                                                \
     && curl -L ${varUrlOpm}                                                    \
             -o /bin/opm                                                        \
     && curl -L ${varUrlJq}                                                     \
             -o /bin/jq                                                         \
     && chmod +x /bin/{opm,helm,terraform,jq,grpcurl}                           \
     && terraform version                                                       \
     && chmod +x /usr/bin/entrypoint                                            \
     && mkdir /root/.bak && mv                                                  \
          /root/original-ks.cfg                                                 \
          /root/anaconda-ks.cfg                                                 \
          /root/anaconda-post-nochroot.log                                      \
          /root/anaconda-post.log                                               \
          /root/buildinfo                                                       \
        /root/.bak/                                                             \
    && rm -rf                                                                   \
        /var/cache/*                                                            \
        /var/log/dnf*                                                           \
        /var/log/yum*                                                           \
     && mkdir -p /root/deploy/{mirror,images}                                   \
     && mkdir -p /root/bundle                                                   \
     && mkdir -p /manifests                                                     \
     && mkdir -p /db                                                            \
     && touch /db/bundles.db                                                    \
     && initializer                                                             \
          --manifests /manifests/                                               \
          --output /db/bundles.db                                               \
    && sed -i -e 's|^#mount_program|mount_program|g'                            \
       -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf\
   && echo

RUN set -ex                                                                     \
     && mkdir -p \
                 /var/lib/shared/overlay-images \
                 /var/lib/shared/overlay-layers \
     && touch /var/lib/shared/overlay-images/images.lock \
     && touch /var/lib/shared/overlay-layers/layers.lock \
     && sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf \
    && echo

#################################################################################
# ContainerOne | Cloud Orchestration Tools - Point of Origin
ENV \
  varVerOpenshift="${varVerOpenshift}" \
  varVerTpdk="${varVerOpenshift}"

LABEL \
  name="koffer"                                                                 \
  license=GPLv3                                                                 \
  version="${varVerTpdk}"                                                       \
  vendor="ContainerCraft.io"                                                    \
  build-date="${varRunDate}"                                                    \
  maintainer="ContainerCraft.io"                                                \
  distribution-scope="public"                                                   \
  io.openshift.tags="tpdk koffer"                                               \
  io.k8s.display-name="tpdk-koffer-${varVerTpdk}"                               \
  summary="Koffer agnostic artifact collection engine."                         \
  description="Koffer is designed to automate delarative enterprise artifact supply chain."\
  io.k8s.description="Koffer is designed to automate delarative enterprise artifact supply chain."

ENTRYPOINT ["/usr/bin/koffer"]
WORKDIR /root/koffer

