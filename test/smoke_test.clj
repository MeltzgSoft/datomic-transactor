(ns smoke-test
  (:require [clojure.test :refer [deftest is testing use-fixtures run-tests successful?]]
            [datomic.api :as d]))

(def uri (or (System/getenv "DATOMIC_URI")
             "datomic:sql://smoke-test?jdbc:postgresql://postgres:5432/datomic?user=datomic&password=datomic"))

(def schema
  [{:db/ident       :person/email
    :db/valueType   :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique      :db.unique/identity}
   {:db/ident       :person/name
    :db/valueType   :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident       :person/age
    :db/valueType   :db.type/long
    :db/cardinality :db.cardinality/one}])

(def people
  [{:person/email "ada@example.com"   :person/name "Ada Lovelace" :person/age 36}
   {:person/email "alan@example.com"  :person/name "Alan Turing"  :person/age 41}
   {:person/email "grace@example.com" :person/name "Grace Hopper" :person/age 85}])

(def ^:dynamic *conn* nil)

(defn db-fixture
  "Start every run from a fresh database and remove it afterwards."
  [f]
  (d/delete-database uri)
  (d/create-database uri)
  (let [conn (d/connect uri)]
    @(d/transact conn schema)
    @(d/transact conn people)
    (try
      (binding [*conn* conn] (f))
      (finally
        (d/release conn)
        (d/delete-database uri)))))

(use-fixtures :once db-fixture)

(defn- people-count [db]
  (count (d/q '[:find ?e :where [?e :person/email]] db)))

(deftest schema-installed
  (let [idents (set (d/q '[:find [?i ...] :where [_ :db/ident ?i]] (d/db *conn*)))]
    (is (every? idents [:person/email :person/name :person/age]))))

(deftest insert-and-query
  (let [rows (d/q '[:find ?name ?age
                    :where [?e :person/name ?name]
                           [?e :person/age ?age]]
                  (d/db *conn*))]
    (is (= [["Grace Hopper" 85] ["Alan Turing" 41] ["Ada Lovelace" 36]]
           (sort-by (comp - second) rows)))))

(deftest pull-by-lookup-ref
  (is (= {:person/name "Alan Turing" :person/age 41}
         (d/pull (d/db *conn*) '[:person/name :person/age]
                 [:person/email "alan@example.com"]))))

(deftest upsert-does-not-duplicate
  (testing "re-asserting a unique email updates in place"
    (is (= 3 (people-count (d/db *conn*))))
    (let [{:keys [db-after]} @(d/transact *conn* [{:person/email "ada@example.com"
                                                  :person/age    37}])]
      (is (= 3 (people-count db-after)))
      (is (= 37 (:person/age (d/pull db-after [:person/age] [:person/email "ada@example.com"])))))))

(defn -main [& _]
  (let [result (run-tests 'smoke-test)]
    ;; peer threads are non-daemon; without exiting, the JVM never terminates
    (d/shutdown true)
    (System/exit (if (successful? result) 0 1))))
