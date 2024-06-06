import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import com.ververica.cdc.connectors.mysql.table.StartupOptions;
import com.ververica.cdc.debezium.JsonDebeziumDeserializationSchema;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class DataStreamJob {

    public static void main(String[] args) {
        MySqlSource<String> mySqlSource = MySqlSource.<String>builder()
                .hostname("localhost")
                .port(3306)
                .databaseList("fallen")
                .tableList("fallen.angel", "fallen.gabriel", "fallen.girl")
                .startupOptions(StartupOptions.initial())
                .username("root")
                .password("")
                .deserializer(new JsonDebeziumDeserializationSchema())
                .serverTimeZone("UTC")
                .build();

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(3000);

        env.fromSource(mySqlSource, WatermarkStrategy.noWatermarks(), "MySQL CDC Source")
                .uid("sql-source-uid")
                .setParallelism(1)
                .print()
                .setParallelism(1);

        try {
            env.execute();
        } catch (Exception e) {
            // ... unfortunately
        }
    }
}
