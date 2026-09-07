class NetworkDiagnostics extends tabris.NativeObject {

  get _nativeType() {
    return 'com.eclipsesource.NetworkDiagnostics';
  }

  interfaces() {
    return this._promiseCall('interfaces', {});
  }

  gateways({timeoutSeconds} = {}) {
    return this._promiseCall('gateways', {timeoutSeconds});
  }

  dnsServers() {
    return this._promiseCall('dnsServers', {});
  }

  ping(host, {packetCount, timeoutSeconds} = {}) {
    return this._promiseCall('ping', {host, packetCount, timeoutSeconds});
  }

  dnsQuery(domain, {server, timeoutSeconds} = {}) {
    return this._promiseCall('dnsQuery', {domain, server, timeoutSeconds});
  }

  http(url, {method, timeoutSeconds} = {}) {
    return this._promiseCall('http', {url, method, timeoutSeconds});
  }

  _promiseCall(method, parameters) {
    return new Promise((resolve, reject) => {
      this._nativeCall(method, {
        parameters: withoutUndefined(parameters),
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

// Keys left out by the caller must not reach the bridge as `undefined`; the
// native side treats an absent key as "use the default".
function withoutUndefined(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
}

module.exports = NetworkDiagnostics;
