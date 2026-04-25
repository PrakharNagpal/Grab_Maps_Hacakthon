FROM dart:stable AS build

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline

FROM dart:stable

WORKDIR /app

COPY --from=build /app /app

ENV PORT=8080
EXPOSE 8080

CMD ["dart", "run", "bin/server.dart"]
