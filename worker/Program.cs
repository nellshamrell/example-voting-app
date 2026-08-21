using System;
using System.Data.Common;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Newtonsoft.Json;
using Npgsql;
using StackExchange.Redis;

namespace Worker
{
    public class Program
    {
        public static int Main(string[] args)
        {
            try
            {
                var pgsql = OpenDbConnection(BuildPostgresConnectionString());
                var redisConn = OpenRedisConnection();
                var redis = redisConn.GetDatabase();

                // Keep alive is not implemented in Npgsql yet. This workaround was recommended:
                // https://github.com/npgsql/npgsql/issues/1214#issuecomment-235828359
                var keepAliveCommand = pgsql.CreateCommand();
                keepAliveCommand.CommandText = "SELECT 1";

                var definition = new { vote = "", voter_id = "" };
                while (true)
                {
                    // Slow down to prevent CPU spike, only query each 100ms
                    Thread.Sleep(100);

                    // Reconnect redis if down
                    if (redisConn == null || !redisConn.IsConnected) {
                        Console.WriteLine("Reconnecting Redis");
                        redisConn?.Dispose();
                        redisConn = OpenRedisConnection();
                        redis = redisConn.GetDatabase();
                    }
                    string json = redis.ListLeftPopAsync("votes").Result;
                    if (json != null)
                    {
                        var vote = JsonConvert.DeserializeAnonymousType(json, definition);
                        Console.WriteLine($"Processing vote for '{vote.vote}' by '{vote.voter_id}'");
                        // Reconnect DB if down
                        if (!pgsql.State.Equals(System.Data.ConnectionState.Open))
                        {
                            Console.WriteLine("Reconnecting DB");
                            pgsql = OpenDbConnection(BuildPostgresConnectionString());
                        }
                        else
                        { // Normal +1 vote requested
                            UpdateVote(pgsql, vote.voter_id, vote.vote);
                        }
                    }
                    else
                    {
                        keepAliveCommand.ExecuteNonQuery();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
        }

        private static string BuildPostgresConnectionString()
        {
            var builder = new NpgsqlConnectionStringBuilder
            {
                Host = GetEnvironmentVariable("POSTGRES_HOST", "db"),
                Port = int.Parse(GetEnvironmentVariable("POSTGRES_PORT", "5432")),
                Username = GetEnvironmentVariable("POSTGRES_USER", "postgres"),
                Password = GetEnvironmentVariable("POSTGRES_PASSWORD", "postgres"),
                Database = GetEnvironmentVariable("POSTGRES_DB", "postgres")
            };

            if (GetEnvironmentVariable("POSTGRES_SSLMODE", "disable")
                .Equals("require", StringComparison.OrdinalIgnoreCase))
            {
                builder.SslMode = SslMode.Require;
                builder.TrustServerCertificate = true;
            }

            return builder.ConnectionString;
        }

        private static NpgsqlConnection OpenDbConnection(string connectionString)
        {
            NpgsqlConnection connection;

            while (true)
            {
                try
                {
                    connection = new NpgsqlConnection(connectionString);
                    connection.Open();
                    break;
                }
                catch (SocketException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
                catch (DbException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
            }

            Console.Error.WriteLine("Connected to db");

            var command = connection.CreateCommand();
            command.CommandText = @"CREATE TABLE IF NOT EXISTS votes (
                                        id VARCHAR(255) NOT NULL UNIQUE,
                                        vote VARCHAR(255) NOT NULL
                                    )";
            command.ExecuteNonQuery();

            return connection;
        }

        private static ConnectionMultiplexer OpenRedisConnection()
        {
            var redisUrl = Environment.GetEnvironmentVariable("REDIS_URL");
            if (!string.IsNullOrEmpty(redisUrl))
            {
                while (true)
                {
                    try
                    {
                        return OpenRedisUrl(redisUrl);
                    }
                    catch (RedisConnectionException)
                    {
                        Console.Error.WriteLine("Waiting for redis");
                        Thread.Sleep(1000);
                    }
                }
            }

            var hostname = GetEnvironmentVariable("REDIS_HOST", "redis");

            // Use IP address to workaround https://github.com/StackExchange/StackExchange.Redis/issues/410
            var ipAddress = GetIp(hostname);
            Console.WriteLine($"Found redis at {ipAddress}");

            while (true)
            {
                try
                {
                    Console.Error.WriteLine("Connecting to redis");
                    return ConnectionMultiplexer.Connect(ipAddress);
                }
                catch (RedisConnectionException)
                {
                    Console.Error.WriteLine("Waiting for redis");
                    Thread.Sleep(1000);
                }
            }
        }

        private static ConnectionMultiplexer OpenRedisUrl(string redisUrl)
        {
            var schemeSeparator = redisUrl.IndexOf("://", StringComparison.Ordinal);
            var scheme = redisUrl.Substring(0, schemeSeparator);
            var address = redisUrl.Substring(schemeSeparator + 3);
            var atSeparator = address.LastIndexOf('@');
            var credentials = address.Substring(0, atSeparator);
            var endpoint = address.Substring(atSeparator + 1);
            var credentialSeparator = credentials.IndexOf(':');
            var username = credentials.Substring(0, credentialSeparator);
            var password = credentials.Substring(credentialSeparator + 1);
            var portSeparator = endpoint.LastIndexOf(':');
            var hostname = endpoint.Substring(0, portSeparator);
            var port = int.Parse(endpoint.Substring(portSeparator + 1));

            var options = new ConfigurationOptions
            {
                Ssl = scheme.Equals("rediss", StringComparison.OrdinalIgnoreCase)
            };
            options.EndPoints.Add(hostname, port);

            if (!string.IsNullOrEmpty(username))
            {
                options.User = username;
            }
            options.Password = password;

            return ConnectionMultiplexer.Connect(options);
        }

        private static string GetEnvironmentVariable(string name, string defaultValue)
            => Environment.GetEnvironmentVariable(name) ?? defaultValue;

        private static string GetIp(string hostname)
            => Dns.GetHostEntryAsync(hostname)
                .Result
                .AddressList
                .First(a => a.AddressFamily == AddressFamily.InterNetwork)
                .ToString();

        private static void UpdateVote(NpgsqlConnection connection, string voterId, string vote)
        {
            var command = connection.CreateCommand();
            try
            {
                command.CommandText = "INSERT INTO votes (id, vote) VALUES (@id, @vote)";
                command.Parameters.AddWithValue("@id", voterId);
                command.Parameters.AddWithValue("@vote", vote);
                command.ExecuteNonQuery();
            }
            catch (DbException)
            {
                command.CommandText = "UPDATE votes SET vote = @vote WHERE id = @id";
                command.ExecuteNonQuery();
            }
            finally
            {
                command.Dispose();
            }
        }
    }
}
