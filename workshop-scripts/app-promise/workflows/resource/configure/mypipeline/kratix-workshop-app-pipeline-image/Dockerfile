FROM "alpine"

# Install dependencies
RUN apk update && apk add --no-cache \
    yq \
    curl \
    ruby \
    # Add dependencies for kubectl
    ca-certificates \
    bash \
    && rm -rf /var/cache/apk/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/kubectl

# Install terraform CLI
RUN curl https://releases.hashicorp.com/terraform/1.7.1/terraform_1.7.1_linux_amd64.zip -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/terraform && \
    rm terraform.zip

ADD scripts/* /usr/bin/
ADD resources resources

RUN chmod +x /usr/bin/*

#CMD [ "sh", "-c", "resource-configure" ]
ENTRYPOINT []
