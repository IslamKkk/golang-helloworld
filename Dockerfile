FROM golang:1.27.3-alpine AS build

ARG APP_VERSION=local

WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /service .

FROM scratch

ARG APP_VERSION=local
ENV APP_VERSION=${APP_VERSION}
ENV PORT=8080
COPY --from=build /service /service
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/service"]
