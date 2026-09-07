class NetworkDiagnostics extends tabris.NativeObject {

  get _nativeType() {
    return 'com.eclipsesource.NetworkDiagnostics';
  }

  interfaces() {
    return this._promiseCall('interfaces', {});
  }

  gateways(options = {}) {
    return this._promiseCall('gateways', options, ['timeoutSeconds']);
  }

  dnsServers() {
    return this._promiseCall('dnsServers', {});
  }

  ping(host, options = {}) {
    return this._promiseCall('ping', options, ['packetCount', 'timeoutSeconds'], {host});
  }

  dnsQuery(domain, options = {}) {
    return this._promiseCall('dnsQuery', options, ['server', 'timeoutSeconds'], {domain});
  }

  http(url, options = {}) {
    return this._promiseCall('http', options, ['method', 'timeoutSeconds'], {url});
  }

  diagnose(configuration = {}) {
    return this._promiseCall('diagnose', configuration, [
      'pingHosts', 'httpHosts', 'dnsTestDomains', 'timeoutPerHostSeconds', 'pingPacketCount', 'httpMethod'
    ]);
  }

  cancel() {
    return this._promiseCall('cancel', {});
  }

  _promiseCall(method, options, keys = [], positional = {}) {
    if (!isPlainObject(options)) {
      return invalidParameter(`options of ${method}() must be an object, received ${describe(options)}`);
    }
    const parameters = withoutUndefined({...positional, ...pick(options, keys)});
    return new Promise((resolve, reject) => {
      this._nativeCall(method, {
        parameters,
        completion: (error, result) => {
          if (error != null) {
            const rejection = new Error(error.message);
            rejection.code = error.code;
            reject(rejection);
          } else {
            resolve(result === undefined ? null : result);
          }
        }
      });
    });
  }

}

tabris.NativeObject.defineEvents(NetworkDiagnostics.prototype, {
  stageStarted: {native: true},
  stageFinished: {native: true},
  gatewayResult: {native: true},
  dnsServerResult: {native: true},
  pingResult: {native: true},
  httpResult: {native: true}
});

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function pick(object, keys) {
  return Object.fromEntries(keys.filter(key => key in object).map(key => [key, object[key]]));
}

// Keys left out by the caller must not reach the bridge as `undefined`; the
// native side treats an absent key as "use the default".
function withoutUndefined(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
}

function invalidParameter(message) {
  const error = new Error(message);
  error.code = 'invalidParameter';
  return Promise.reject(error);
}

function describe(value) {
  return Array.isArray(value) ? 'an array' : value === null ? 'null' : typeof value;
}

module.exports = NetworkDiagnostics;
