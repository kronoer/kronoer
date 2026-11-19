FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
    -o /out/kronoerserver ./cmd/kronoerserver

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/kronoerserver /kronoerserver
EXPOSE 8080
ENTRYPOINT ["/kronoerserver"]
CMD ["serve"]
