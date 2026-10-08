(require '[datomic.api :as d])

(def uri (or (System/getenv "DATOMIC_URI")
             "datomic:sql://smoke-test?jdbc:postgresql://postgres:5432/datomic?user=datomic&password=datomic"))

(println "create-database ->" (d/create-database uri))
(def conn (d/connect uri))

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

@(d/transact conn schema)
(println "schema installed")

;; email is a unique identity, so re-running upserts instead of duplicating
@(d/transact conn
   [{:person/email "ada@example.com"   :person/name "Ada Lovelace" :person/age 36}
    {:person/email "alan@example.com"  :person/name "Alan Turing"   :person/age 41}
    {:person/email "grace@example.com" :person/name "Grace Hopper"  :person/age 85}])
(println "data inserted")

(let [db (d/db conn)]
  (println "\nnames and ages, oldest first:")
  (doseq [[n a] (sort-by (comp - second)
                         (d/q '[:find ?name ?age
                                :where [?e :person/name ?name]
                                       [?e :person/age ?age]]
                              db))]
    (println " " n a))
  (println "\npull by email:")
  (prn (d/pull db '[:person/name :person/age] [:person/email "alan@example.com"]))
  (assert (= 3 (count (d/q '[:find ?e :where [?e :person/email]] db)))
          "expected exactly 3 people"))

(println "\nOK")
(d/shutdown true) ; peer threads are non-daemon; without this the JVM never exits
