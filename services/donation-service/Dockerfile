ARG GO_VERSION=1.25.7-alpine
ARG ALPINE_VERSION=3.20

# Estágio 1: Compilação do binário estático
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS builder

ARG TARGETOS=linux
ARG TARGETARCH=arm64

WORKDIR /src

# Copia apenas os manifestos primeiro para otimizar o cache de camadas
COPY go.mod ./
RUN go mod download

# Copia o restante do código-fonte
COPY . .

# Compila o binário estático sem dependências C (CGO_ENABLED=0)
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /out/donation-service .

# Estágio 2: Imagem final mínima e segura
FROM alpine:${ALPINE_VERSION}

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Certificados CA são obrigatórios para comunicação TLS com a API do AWS SQS
RUN apk --no-cache add ca-certificates

COPY --from=builder /out/donation-service .

USER appuser

EXPOSE 8082

ENTRYPOINT ["./donation-service"]