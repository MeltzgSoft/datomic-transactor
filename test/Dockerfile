# Stand-in for an external application: plain Clojure image, Datomic peer from Maven Central.
# It shares nothing with the transactor image.
FROM clojure:tools-deps
WORKDIR /app
COPY deps.edn .
RUN clojure -P
COPY smoke_test.clj logback.xml ./
CMD ["clojure", "-M", "-m", "smoke-test"]
