-- Databricks notebook source
-- MAGIC %md-sandbox
-- MAGIC 
-- MAGIC <div style="text-align: center; line-height: 0; padding-top: 9px;">
-- MAGIC   <img src="https://databricks.com/wp-content/uploads/2018/03/db-academy-rgb-1200px.png" alt="Databricks Learning" style="width: 600px">
-- MAGIC </div>

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC # Delta Lakeの高度な機能（Advanced Delta Lake Features）
-- MAGIC 
-- MAGIC Delta Lakeを使った基本的なデータタスクに慣れてきたので、Delta Lake独自のいくつかの機能について説明します。
-- MAGIC 
-- MAGIC ここで使用するキーワードには標準的なANSI SQLの一部ではないものもありますが、SQLを使えば、DatabricksでのDelta Lakeの全操作が実行可能であることに注意してください。
-- MAGIC 
-- MAGIC ## 学習目標（Learning Objectives）
-- MAGIC このレッスンでは、以下のことが学べます。
-- MAGIC * **`OPTIMIZE`**を使って小さなファイルを圧縮する
-- MAGIC * **`ZORDER`**を使ってテーブルにインデックスを付ける
-- MAGIC * Delta Lakeファイルのディレクトリ構造を記述する
-- MAGIC * テーブルトランザクション履歴を確認する
-- MAGIC * 以前のテーブルバージョンを照会して、そのバージョンにロールバックする
-- MAGIC * **`VACUUM`**で古いデータファイルをクリーンアップする
-- MAGIC 
-- MAGIC **リソース**
-- MAGIC * <a href="https://docs.databricks.com/spark/latest/spark-sql/language-manual/delta-optimize.html" target="_blank">Delta Optimize - Databricksドキュメント</a>
-- MAGIC * <a href="https://docs.databricks.com/spark/latest/spark-sql/language-manual/delta-vacuum.html" target="_blank">Delta Vacuum - Databricksドキュメント</a>

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## セットアップを実行する（Run Setup）
-- MAGIC まずはセットアップスクリプトを実行します。 セットアップスクリプトは、ユーザー名、ユーザーホーム、各ユーザーを対象とするデータベースを定義します。

-- COMMAND ----------

-- MAGIC %run ../Includes/Classroom-Setup-2.3

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## 履歴のあるDeltaテーブルを作成する（Creating a Delta Table with History）
-- MAGIC 
-- MAGIC 以下のセルは前のレッスンの全トランザクションを1つのセルに圧縮します。 （**`DROP TABLE`**を除いて！）
-- MAGIC 
-- MAGIC このクエリが実行されるのを待つ間に、実行されるトランザクションの総数を確認できるかどうか考えてください。

-- COMMAND ----------

CREATE TABLE students
  (id INT, name STRING, value DOUBLE);
  
INSERT INTO students VALUES (1, "Yve", 1.0);
INSERT INTO students VALUES (2, "Omar", 2.5);
INSERT INTO students VALUES (3, "Elia", 3.3);

INSERT INTO students
VALUES 
  (4, "Ted", 4.7),
  (5, "Tiffany", 5.5),
  (6, "Vini", 6.3);
  
UPDATE students 
SET value = value + 1
WHERE name LIKE "T%";

DELETE FROM students 
WHERE value > 6;

CREATE OR REPLACE TEMP VIEW updates(id, name, value, type) AS VALUES
  (2, "Omar", 15.2, "update"),
  (3, "", null, "delete"),
  (7, "Blue", 7.7, "insert"),
  (11, "Diya", 8.8, "update");
  
MERGE INTO students b
USING updates u
ON b.id=u.id
WHEN MATCHED AND u.type = "update"
  THEN UPDATE SET *
WHEN MATCHED AND u.type = "delete"
  THEN DELETE
WHEN NOT MATCHED AND u.type = "insert"
  THEN INSERT *;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## テーブルの詳細を調べる（Examine Table Details）
-- MAGIC 
-- MAGIC DatabricksはデフォルトではHiveメタストアを使用して、データベース、テーブル、ビューを登録します。
-- MAGIC 
-- MAGIC **`DESCRIBE EXTENDED`**を使うと、テーブルに関する重要なメタデータを確認できます。

-- COMMAND ----------

DESCRIBE EXTENDED students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC **`Location`**行に注意してください。
-- MAGIC 
-- MAGIC これまでは、テーブルをデータベース内の単なるリレーショナルエンティティとして考えてきましたが、Delta Lakeテーブルは実のところ、クラウドオブジェクトストレージに保存されたファイルのコレクションを元にしています。

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## Delta Lakeファイルを調べる（Explore Delta Lake Files）
-- MAGIC 
-- MAGIC Databricksユーティリティ機能を使うと、Delta Lakeテーブルの元となるファイルを確認できます。
-- MAGIC 
-- MAGIC **注**：今のところ、Delta Lakeで作業するにはこれらのファイルについてすべてを知ることは重要ではありませんが、技術がどのように実装されているかについて理解を深めるのに役立ちます。

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{DA.paths.user_db}/students"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ディレクトリには、多数のParquetデータファイルと**`_delta_log`**というのディレクトリが含まれていることに注意してください。
-- MAGIC 
-- MAGIC Delta Lakeテーブルのレコードは、Parquetファイルにデータとして保存されています。
-- MAGIC 
-- MAGIC Delta Lakeテーブルへのトランザクションは**`_delta_log`**に記録されます。
-- MAGIC 
-- MAGIC **`_delta_log`**の中をのぞいて、詳細を確認できます。

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{DA.paths.user_db}/students/_delta_log"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC 各トランザクションごとに、新しいJSONファイルがDelta Lakeトランザクションログに書き込まれます。 ここでは、このテーブル（Delta Lakeのインデックスは0から始まります）に対して合計8つのトランザクションがあることがわかります。

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## データファイルについて推論する（Reasoning about Data Files）
-- MAGIC 
-- MAGIC 明らかにとても小さなテーブルについて、たくさんのデータファイルを確認したところです。
-- MAGIC 
-- MAGIC **`DESCRIBE DETAIL`**で、ファイル数など、Deltaテーブルについてのいくつかの他の詳細を確認することができます。

-- COMMAND ----------

DESCRIBE DETAIL students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ここでは、現バージョンのテーブルに、現在3つのデータファイルが含まれていることがわかります。 では、なんでこれら他のParquetファイルがテーブルディレクトリに入っているのでしょうか？
-- MAGIC 
-- MAGIC Delta Lakeは、変更データを含むファイルを上書きしたり、すぐに削除したりするのではなく、トランザクションログを使って、現バージョンのテーブルでファイルが有効であるかどうかを示します。
-- MAGIC 
-- MAGIC ここでは、レコードが挿入され、更新され、削除された上の**`MERGE`**文に対応するトランザクションログを見てみます。

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(spark.sql(f"SELECT * FROM json.`{DA.paths.user_db}/students/_delta_log/00000000000000000007.json`"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC **`add`**列には、テーブルに書き込まれる新しいすべてのファイルのリストが含まれています。**`remove`**列は、もうテーブルに含めるべきでないファイルを示しています。
-- MAGIC 
-- MAGIC Delta Lakeテーブルを照会する場合、クエリエンジンはトランザクションログを使って、現バージョンで有効なファイルをすべて特定し、他のデータファイルはすべて無視します。

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## 小さなファイルの圧縮とインデックスの作成（Compacting Small Files and Indexing）
-- MAGIC 
-- MAGIC ファイルが小さくなってしまうのにはさまざま理由があります。今回の例では数多くの操作を行い、1つまたは複数のレコードが挿入されました。
-- MAGIC 
-- MAGIC **`OPTIMIZE`**コマンドを使うと、ファイルは最適なサイズ（テーブルの大きさに基づいて調整）になるように結合されます。
-- MAGIC 
-- MAGIC **`OPTIMIZE`**は、レコードを結合させて結果を書き直すことで、既存のデータを置き換えます。
-- MAGIC 
-- MAGIC **`OPTIMIZE`**を実行する場合、ユーザーはオプションで**`ZORDER`**インデックスのために、1つか複数のフィールドを指定できます。 Zオーダーの具体的な計算方法は重要ではありませんが、データファイル内で似たような値のデータを同じ位置に配置することにより、指定したフィールドでフィルタリングする際のデータ検索を高速化します。

-- COMMAND ----------

OPTIMIZE students
ZORDER BY id

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ここで扱うデータは非常に小さいので、**`ZORDER`**のメリットは何もありませんが、この操作によって生じるメトリックスをすべて確認できます。

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## Delta Lakeトランザクションの確認（Reviewing Delta Lake Transactions）
-- MAGIC 
-- MAGIC Delta Lakeテーブルの変更はすべてトランザクションログに保存されるので、<a href="https://docs.databricks.com/spark/2.x/spark-sql/language-manual/describe-history.html" target="_blank">テーブルの履歴</a>は簡単に確認できます。

-- COMMAND ----------

DESCRIBE HISTORY students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC 期待通り、**`OPTIMIZE`**はテーブルの別バージョンを作成したので、バージョン8が最新のバージョンになります。
-- MAGIC 
-- MAGIC トランザクションログに削除済みと印を付けられた追加のデータファイルがあったのを覚えていますか？ これにより、テーブルの以前のバージョンを照会できます。
-- MAGIC 
-- MAGIC こうしたタイムトラベルクエリは、整数バージョンかタイムスタンプのいずれかを指定することで実行できます。
-- MAGIC 
-- MAGIC **注**：ほとんどの場合、タイムスタンプを使って関心がある時点のデータを再作成します。 バージョンは決定論的なので、（いつこのデモを実行しているかは分からないので）デモではバージョンを使用します。

-- COMMAND ----------

SELECT * 
FROM students VERSION AS OF 3

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC タイムトラベルについて注意すべきなのは、現バージョンに対するトランザクションを取り消すことにより、以前の状態のテーブルを再作成しているわけではなく、指定されたバージョンの時点で有効と示されたすべてのデータファイルを照会しているだけだということです。

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## バージョンのロールバック（Rollback Versions）
-- MAGIC 
-- MAGIC テーブルから手動でいくつかのレコードを削除するクエリを書いていて、うっかりこのクエリを次の状態で実行するとします。

-- COMMAND ----------

DELETE FROM students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC 削除の影響を受けた列の数に**`-1`**が表示されている場合、データのディレクトリ全体が削除されたことに注意してください。
-- MAGIC 
-- MAGIC 以下でこれを確認しましょう。

-- COMMAND ----------

SELECT * FROM students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC テーブルのすべてのレコードを削除することは、たぶん望んだ結果ではありません。 幸い、このコミットを簡単にロールバックすることができます。

-- COMMAND ----------

RESTORE TABLE students TO VERSION AS OF 8 

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC **`RESTORE`**<a href="https://docs.databricks.com/spark/latest/spark-sql/language-manual/delta-restore.html" target="_blank">コマンド</a>がトランザクションとして記録されていることに注意してください。うっかり、テーブルのレコードをすべて削除してしまったという事実は完全には隠せませんが、この操作を取り消し、テーブルを望ましい状態に戻すことはできます。

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC ## 古いファイルのクリーンアップ（Cleaning Up Stale Files）
-- MAGIC 
-- MAGIC MAGIC Databricksは、Delta Lakeテーブルの古いファイルを自動的にクリーンアップします。
-- MAGIC 
-- MAGIC Delta Lakeのバージョン管理とタイムトラベルは、少し前のバージョンを照会したり、クエリをロールバックするには素晴らしいのですが、大きなプロダクションテーブルの全バージョンのデータファイルを無期限に手元に置いておくのは非常に高くつきます（またPIIがある場合はコンプライアンスの問題につながる可能性があります）。
-- MAGIC 
-- MAGIC 手動で古いデータファイルをパージしたい場合、これは**`VACUUM`**操作で実行できます。
-- MAGIC 
-- MAGIC 次のセルのコメントアウトを外し、**`0 HOURS`**の保持で実行して、現バージョンだけを保持してください：

-- COMMAND ----------

-- VACUUM students RETAIN 0 HOURS

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC デフォルトでは、**`VACUUM`**は7日間未満のファイルを削除できないようにします。これは、長時間実行される操作が削除対象ファイルを参照しないようにするためです。 Deltaテーブルに対して**`VACUUM`**を実行すると、指定したデータ保持期間以前のバージョンにタイムトラベルで戻れなくなります。  デモでは、Databricksが**`0 HOURS`**の保持を指定したコードを実行するのが表示されるかもしれません。 これはあくまで、この機能を示すためであり、通常、本番環境ではこのようなことはしません。
-- MAGIC 
-- MAGIC 次のセルでは：
-- MAGIC 1. チェックをオフにして、データファイルの早すぎる削除を防ぐ
-- MAGIC 1. **`VACUUM`**コマンドのロギングが有効になっていることを確認する
-- MAGIC 1. VACUUMの**`DRY RUN`**バージョンを使って、削除対象の全レコードを表示する

-- COMMAND ----------

SET spark.databricks.delta.retentionDurationCheck.enabled = false;
SET spark.databricks.delta.vacuum.logging.enabled = true;

VACUUM students RETAIN 0 HOURS DRY RUN

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC **`VACUUM`**を実行して上の9つのファイルを削除することで、これらのファイルの具現化を必要とするバージョンのテーブルへのアクセスを永久に削除します。

-- COMMAND ----------

VACUUM students RETAIN 0 HOURS

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC テーブルディレクトリを確認して、ファイルが正常に削除されたことを示します。

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{DA.paths.user_db}/students"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC 
-- MAGIC 次のセルを実行して、このレッスンに関連するテーブルとファイルを削除してください。

-- COMMAND ----------

-- MAGIC %python
-- MAGIC DA.cleanup()

-- COMMAND ----------

-- MAGIC %md-sandbox
-- MAGIC &copy; 2022 Databricks, Inc. All rights reserved.<br/>
-- MAGIC Apache, Apache Spark, Spark and the Spark logo are trademarks of the <a href="https://www.apache.org/">Apache Software Foundation</a>.<br/>
-- MAGIC <br/>
-- MAGIC <a href="https://databricks.com/privacy-policy">Privacy Policy</a> | <a href="https://databricks.com/terms-of-use">Terms of Use</a> | <a href="https://help.databricks.com/">Support</a>
