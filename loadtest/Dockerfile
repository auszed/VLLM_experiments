# Build a static binary, run it anywhere without a Go toolchain.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /loadtest .

FROM alpine:3.20
COPY --from=build /loadtest /usr/local/bin/loadtest
ENTRYPOINT ["loadtest"]
