package config

import "testing"

func env(vars map[string]string) func(string) string {
	return func(name string) string { return vars[name] }
}

func TestLoadDefaults(t *testing.T) {
	c, err := Load(env(map[string]string{"KRONOER_DATABASE_URL": "postgres://db"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.Addr != ":8080" || c.LogFormat != "json" || c.S3.Region != "us-east-1" {
		t.Errorf("got %+v, want the defaults", c)
	}
}

func TestLoadRejects(t *testing.T) {
	for name, vars := range map[string]map[string]string{
		"no database":    {},
		"bad log format": {"KRONOER_DATABASE_URL": "postgres://db", "KRONOER_LOG_FORMAT": "xml"},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := Load(env(vars)); err == nil {
				t.Error("got no error")
			}
		})
	}
}

func TestS3Validate(t *testing.T) {
	full := S3{Bucket: "kronoer", AccessKey: "a", SecretKey: "s"}
	if err := full.Validate(); err != nil {
		t.Errorf("full settings: %v", err)
	}
	noBucket := full
	noBucket.Bucket = ""
	if err := noBucket.Validate(); err == nil {
		t.Error("missing bucket: got no error")
	}
}
